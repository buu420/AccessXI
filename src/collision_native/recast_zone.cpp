#include "collision_native/recast_zone.h"

#include "collision_native/collision_world.h"

#include <DetourNavMesh.h>
#include <DetourNavMeshBuilder.h>
#include <DetourNavMeshQuery.h>
#include <PartitionedMesh.h>
#include <Recast.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <numbers>
#include <string>
#include <utility>
#include <vector>

namespace accessxi::collision {
namespace {

// The native library shares FFXI's 32-bit process.  A 0.20-yalm full-zone grid
// needs 2,530 tiles for East Ronfaure and can exhaust or fragment the game's
// address space.  A 0.50-yalm grid keeps the full-zone build practical in the
// 32-bit client while conservatively rounding the
// 0.40-yalm player clearance up to one cell.  Every resulting segment is still
// accepted only after the original-triangle Bullet capsule/step sweep below.
constexpr float cell_size = 0.50f;
constexpr float cell_height = 0.10f;
constexpr float agent_height = 1.80f;
constexpr float agent_radius = 0.40f;
constexpr float agent_max_climb = 0.60f;
constexpr float agent_max_slope = 50.0f;
constexpr int tile_size = 96;
constexpr int max_edge_length = 60;
constexpr float max_simplification_error = 0.3f;
constexpr int min_region_area = 64;
constexpr int merge_region_area = 400;
constexpr int max_vertices_per_polygon = 6;
constexpr float detail_sample_distance = 1.20f;
constexpr float detail_sample_max_error = 0.10f;
constexpr unsigned short walk_flag = 0x01u;

bool finite_vec3(const Vec3& value) noexcept
{
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z);
}

float distance(const Vec3& left, const Vec3& right)
{
    const float x = left.x - right.x;
    const float y = left.y - right.y;
    const float z = left.z - right.z;
    return std::sqrt(x * x + y * y + z * z);
}

float horizontal_distance(const Vec3& left, const Vec3& right)
{
    const float x = left.x - right.x;
    const float z = left.z - right.z;
    return std::sqrt(x * x + z * z);
}

bool segment_has_walkable_support(
    dtNavMeshQuery* nav_query,
    const dtQueryFilter& filter,
    const Vec3& start,
    const Vec3& end)
{
    const float horizontal = horizontal_distance(start, end);
    const int sample_count = std::max(2, static_cast<int>(std::ceil(horizontal / cell_size)));
    const float extents[3]{agent_radius + 0.10f, agent_height, agent_radius + 0.10f};
    float previous_height = start.y;
    for (int sample_index = 1; sample_index < sample_count; ++sample_index)
    {
        const float fraction = static_cast<float>(sample_index)
            / static_cast<float>(sample_count);
        const float sample[3]{
            start.x + (end.x - start.x) * fraction,
            start.y + (end.y - start.y) * fraction,
            start.z + (end.z - start.z) * fraction,
        };
        dtPolyRef reference = 0;
        float supported[3]{};
        if (dtStatusFailed(nav_query->findNearestPoly(
                sample,
                extents,
                &filter,
                &reference,
                supported))
            || reference == 0)
        {
            return false;
        }
        const Vec3 supported_point{supported[0], supported[1], supported[2]};
        // A nearby polygon is not proof of floor underneath the player.  The
        // former radius-sized allowance let samples beside La Theine's steep
        // bank snap laterally across the navmesh boundary and certified the
        // exact pocket where the live character stopped.  Require support
        // essentially beneath each half-cell sample instead.
        if (horizontal_distance(supported_point, Vec3{sample[0], sample[1], sample[2]})
                > cell_height
            || std::fabs(supported_point.y - sample[1]) > agent_height
            || std::fabs(supported_point.y - previous_height) > agent_max_climb + cell_height)
        {
            return false;
        }
        previous_height = supported_point.y;
    }
    return std::fabs(end.y - previous_height) <= agent_max_climb + cell_height;
}

bool traversable_capsule_segment(
    const CollisionWorld& collision_world,
    const Vec3& start,
    const Vec3& end,
    const bool allow_long_step)
{
    if (collision_world.sweep_capsule(start, end, agent_radius, agent_height).clear)
    {
        return true;
    }

    // FFXI's character controller steps over short collision lips.  This is a
    // local step, not permission to float a raised capsule across an arbitrary
    // long segment.  The old unbounded raised sweep accepted the 14-yalm La
    // Theine cliff approach even though the live controller stopped there.
    if (!allow_long_step && horizontal_distance(start, end) > 1.5f)
    {
        return false;
    }

    constexpr float step_clearance = agent_max_climb + 0.05f;
    const Vec3 raised_start{start.x, start.y + step_clearance, start.z};
    const Vec3 raised_end{end.x, end.y + step_clearance, end.z};
    return collision_world.sweep_capsule(start, raised_start, agent_radius, agent_height).clear
        && collision_world.sweep_capsule(raised_start, raised_end, agent_radius, agent_height).clear
        && collision_world.sweep_capsule(raised_end, end, agent_radius, agent_height).clear;
}

unsigned int next_power_of_two(unsigned int value)
{
    if (value == 0u)
    {
        return 1u;
    }
    --value;
    value |= value >> 1u;
    value |= value >> 2u;
    value |= value >> 4u;
    value |= value >> 8u;
    value |= value >> 16u;
    return value + 1u;
}

unsigned int integer_log2(unsigned int value)
{
    unsigned int result = 0u;
    while (value > 1u)
    {
        value >>= 1u;
        ++result;
    }
    return result;
}

template <typename T, void (*FreeFunction)(T*)>
using RcPointer = std::unique_ptr<T, decltype(FreeFunction)>;

using HeightfieldPointer = RcPointer<rcHeightfield, rcFreeHeightField>;
using CompactHeightfieldPointer = RcPointer<rcCompactHeightfield, rcFreeCompactHeightfield>;
using ContourSetPointer = RcPointer<rcContourSet, rcFreeContourSet>;
using PolyMeshPointer = RcPointer<rcPolyMesh, rcFreePolyMesh>;
using PolyMeshDetailPointer = RcPointer<rcPolyMeshDetail, rcFreePolyMeshDetail>;

struct NavMeshDeleter final
{
    void operator()(dtNavMesh* value) const noexcept
    {
        if (value != nullptr)
        {
            dtFreeNavMesh(value);
        }
    }
};

struct NavQueryDeleter final
{
    void operator()(dtNavMeshQuery* value) const noexcept
    {
        if (value != nullptr)
        {
            dtFreeNavMeshQuery(value);
        }
    }
};

using NavMeshPointer = std::unique_ptr<dtNavMesh, NavMeshDeleter>;
using NavQueryPointer = std::unique_ptr<dtNavMeshQuery, NavQueryDeleter>;

struct TileBuildResult final
{
    unsigned char* data = nullptr;
    int size = 0;
};

bool polygon_center(
    dtNavMesh* nav_mesh,
    dtNavMeshQuery* nav_query,
    const dtPolyRef reference,
    Vec3& result)
{
    const dtMeshTile* tile = nullptr;
    const dtPoly* polygon = nullptr;
    if (dtStatusFailed(nav_mesh->getTileAndPolyByRef(reference, &tile, &polygon))
        || tile == nullptr
        || polygon == nullptr
        || polygon->vertCount == 0)
    {
        return false;
    }
    float center[3]{};
    for (unsigned int index = 0; index < polygon->vertCount; ++index)
    {
        const float* vertex = tile->verts + static_cast<std::size_t>(polygon->verts[index]) * 3u;
        center[0] += vertex[0];
        center[1] += vertex[1];
        center[2] += vertex[2];
    }
    const float inverse = 1.0f / static_cast<float>(polygon->vertCount);
    center[0] *= inverse;
    center[1] *= inverse;
    center[2] *= inverse;
    float closest[3]{};
    bool over_polygon = false;
    if (dtStatusFailed(nav_query->closestPointOnPoly(reference, center, closest, &over_polygon)))
    {
        return false;
    }
    result = Vec3{closest[0], closest[1], closest[2]};
    return finite_vec3(result);
}

class PolyFlagGuard final
{
public:
    explicit PolyFlagGuard(dtNavMesh* nav_mesh)
        : nav_mesh_(nav_mesh)
    {
    }

    ~PolyFlagGuard()
    {
        for (const auto& [reference, flags] : disabled_)
        {
            (void)nav_mesh_->setPolyFlags(reference, flags);
        }
    }

    bool disable(const dtPolyRef reference)
    {
        if (reference == 0
            || std::any_of(disabled_.begin(), disabled_.end(), [reference](const auto& item) {
                return item.first == reference;
            }))
        {
            return false;
        }
        unsigned short flags = 0u;
        if (dtStatusFailed(nav_mesh_->getPolyFlags(reference, &flags)) || flags == 0u)
        {
            return false;
        }
        if (dtStatusFailed(nav_mesh_->setPolyFlags(reference, 0u)))
        {
            return false;
        }
        disabled_.emplace_back(reference, flags);
        return true;
    }

private:
    dtNavMesh* nav_mesh_;
    std::vector<std::pair<dtPolyRef, unsigned short>> disabled_;
};

TileBuildResult build_tile(
    rcContext& context,
    const std::vector<float>& vertices,
    const PartitionedMesh& partitioned,
    const int tile_x,
    const int tile_y,
    const float* tile_minimum,
    const float* tile_maximum)
{
    rcConfig config{};
    config.cs = cell_size;
    config.ch = cell_height;
    config.walkableSlopeAngle = agent_max_slope;
    config.walkableHeight = static_cast<int>(std::ceil(agent_height / config.ch));
    config.walkableClimb = static_cast<int>(std::floor(agent_max_climb / config.ch));
    // Radius erosion is followed by an exact Bullet capsule/step check for
    // every emitted segment.
    config.walkableRadius = static_cast<int>(std::ceil(agent_radius / config.cs));
    config.maxEdgeLen = max_edge_length;
    config.maxSimplificationError = max_simplification_error;
    config.minRegionArea = min_region_area;
    config.mergeRegionArea = merge_region_area;
    config.maxVertsPerPoly = max_vertices_per_polygon;
    config.tileSize = tile_size;
    config.borderSize = config.walkableRadius + 3;
    config.width = config.tileSize + config.borderSize * 2;
    config.height = config.tileSize + config.borderSize * 2;
    config.detailSampleDist = detail_sample_distance;
    config.detailSampleMaxError = detail_sample_max_error;
    rcVcopy(config.bmin, tile_minimum);
    rcVcopy(config.bmax, tile_maximum);
    config.bmin[0] -= static_cast<float>(config.borderSize) * config.cs;
    config.bmin[2] -= static_cast<float>(config.borderSize) * config.cs;
    config.bmax[0] += static_cast<float>(config.borderSize) * config.cs;
    config.bmax[2] += static_cast<float>(config.borderSize) * config.cs;

    float query_minimum[2]{config.bmin[0], config.bmin[2]};
    float query_maximum[2]{config.bmax[0], config.bmax[2]};
    std::vector<int> overlapping_nodes;
    partitioned.GetNodesOverlappingRect(query_minimum, query_maximum, overlapping_nodes);
    if (overlapping_nodes.empty())
    {
        return {};
    }

    HeightfieldPointer heightfield(rcAllocHeightfield(), rcFreeHeightField);
    if (heightfield == nullptr
        || !rcCreateHeightfield(
            &context,
            *heightfield,
            config.width,
            config.height,
            config.bmin,
            config.bmax,
            config.cs,
            config.ch))
    {
        throw CollisionError("Recast could not create a tile heightfield.");
    }

    std::vector<unsigned char> triangle_areas(
        static_cast<std::size_t>(std::max(1, partitioned.maxTrisPerChunk)));
    for (const int node_index : overlapping_nodes)
    {
        const PartitionedMesh::Node& node = partitioned.nodes.at(static_cast<std::size_t>(node_index));
        if (node.numTris <= 0)
        {
            continue;
        }
        const int* triangles = partitioned.tris.data() + static_cast<std::size_t>(node.triIndex) * 3u;
        std::fill_n(triangle_areas.begin(), node.numTris, RC_NULL_AREA);
        rcMarkWalkableTriangles(
            &context,
            config.walkableSlopeAngle,
            vertices.data(),
            static_cast<int>(vertices.size() / 3u),
            triangles,
            node.numTris,
            triangle_areas.data());
        if (!rcRasterizeTriangles(
            &context,
            vertices.data(),
            static_cast<int>(vertices.size() / 3u),
            triangles,
            triangle_areas.data(),
            node.numTris,
            *heightfield,
            config.walkableClimb))
        {
            throw CollisionError("Recast could not rasterize a tile.");
        }
    }

    // Do not promote low non-walkable spans to walkable ones. FFXI's DAT
    // collision uses thin vertical wall triangles, and that promotion can
    // erase a wall at a floor contact seam.
    rcFilterLedgeSpans(&context, config.walkableHeight, config.walkableClimb, *heightfield);
    rcFilterWalkableLowHeightSpans(&context, config.walkableHeight, *heightfield);

    CompactHeightfieldPointer compact(rcAllocCompactHeightfield(), rcFreeCompactHeightfield);
    if (compact == nullptr
        || !rcBuildCompactHeightfield(
            &context,
            config.walkableHeight,
            config.walkableClimb,
            *heightfield,
            *compact))
    {
        throw CollisionError("Recast could not build a compact tile heightfield.");
    }
    heightfield.reset();

    if (!rcErodeWalkableArea(&context, config.walkableRadius, *compact)
        || !rcBuildLayerRegions(&context, *compact, config.borderSize, config.minRegionArea))
    {
        throw CollisionError("Recast could not build tile walkable regions.");
    }

    ContourSetPointer contours(rcAllocContourSet(), rcFreeContourSet);
    if (contours == nullptr
        || !rcBuildContours(
            &context,
            *compact,
            config.maxSimplificationError,
            config.maxEdgeLen,
            *contours))
    {
        throw CollisionError("Recast could not build tile contours.");
    }
    if (contours->nconts == 0)
    {
        return {};
    }

    PolyMeshPointer poly_mesh(rcAllocPolyMesh(), rcFreePolyMesh);
    if (poly_mesh == nullptr
        || !rcBuildPolyMesh(&context, *contours, config.maxVertsPerPoly, *poly_mesh))
    {
        throw CollisionError("Recast could not build a tile polygon mesh.");
    }
    if (poly_mesh->npolys == 0)
    {
        return {};
    }

    PolyMeshDetailPointer detail(rcAllocPolyMeshDetail(), rcFreePolyMeshDetail);
    if (detail == nullptr
        || !rcBuildPolyMeshDetail(
            &context,
            *poly_mesh,
            *compact,
            config.detailSampleDist,
            config.detailSampleMaxError,
            *detail))
    {
        throw CollisionError("Recast could not build tile detail geometry.");
    }

    for (int index = 0; index < poly_mesh->npolys; ++index)
    {
        if (poly_mesh->areas[index] == RC_WALKABLE_AREA)
        {
            poly_mesh->areas[index] = 0u;
        }
        poly_mesh->flags[index] = walk_flag;
    }

    dtNavMeshCreateParams params{};
    params.verts = poly_mesh->verts;
    params.vertCount = poly_mesh->nverts;
    params.polys = poly_mesh->polys;
    params.polyAreas = poly_mesh->areas;
    params.polyFlags = poly_mesh->flags;
    params.polyCount = poly_mesh->npolys;
    params.nvp = poly_mesh->nvp;
    params.detailMeshes = detail->meshes;
    params.detailVerts = detail->verts;
    params.detailVertsCount = detail->nverts;
    params.detailTris = detail->tris;
    params.detailTriCount = detail->ntris;
    params.walkableHeight = agent_height;
    params.walkableRadius = agent_radius;
    params.walkableClimb = agent_max_climb;
    params.tileX = tile_x;
    params.tileY = tile_y;
    params.tileLayer = 0;
    rcVcopy(params.bmin, poly_mesh->bmin);
    rcVcopy(params.bmax, poly_mesh->bmax);
    params.cs = config.cs;
    params.ch = config.ch;
    params.buildBvTree = true;

    TileBuildResult result;
    if (!dtCreateNavMeshData(&params, &result.data, &result.size))
    {
        throw CollisionError("Detour could not encode a navigation tile.");
    }
    return result;
}

} // namespace

struct RecastZone::Impl final
{
    Impl(
        const ParsedZoneMesh& mesh,
        const CollisionWorld& collision,
        const std::stop_token stop_token)
        : collision_world(&collision)
        , allow_long_step_segments(mesh.zone_id != 102u)
        , reject_excessive_local_detours(mesh.zone_id == 102u)
    {
        if (mesh.vertices.empty() || mesh.triangles.empty())
        {
            throw CollisionError("Recast requires a nonempty collision mesh.");
        }
        if (mesh.vertices.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())
            || mesh.triangles.size() > static_cast<std::size_t>(std::numeric_limits<int>::max()))
        {
            throw CollisionError("Recast input mesh is too large.");
        }

        std::vector<float> vertices;
        std::vector<int> triangles;
        PartitionedMesh partitioned;
        vertices.reserve(mesh.vertices.size() * 3u);
        float minimum[3]{
            std::numeric_limits<float>::infinity(),
            std::numeric_limits<float>::infinity(),
            std::numeric_limits<float>::infinity(),
        };
        float maximum[3]{
            -std::numeric_limits<float>::infinity(),
            -std::numeric_limits<float>::infinity(),
            -std::numeric_limits<float>::infinity(),
        };
        std::size_t vertex_index = 0u;
        for (const Vec3& vertex : mesh.vertices)
        {
            if ((vertex_index++ % 4096u) == 0u && stop_token.stop_requested())
            {
                throw CollisionError("Terrain mapping was canceled.");
            }
            if (!finite_vec3(vertex))
            {
                throw CollisionError("Recast input contains a nonfinite vertex.");
            }
            vertices.insert(vertices.end(), {vertex.x, vertex.y, vertex.z});
            minimum[0] = std::min(minimum[0], vertex.x);
            minimum[1] = std::min(minimum[1], vertex.y);
            minimum[2] = std::min(minimum[2], vertex.z);
            maximum[0] = std::max(maximum[0], vertex.x);
            maximum[1] = std::max(maximum[1], vertex.y);
            maximum[2] = std::max(maximum[2], vertex.z);
        }

        triangles.reserve(mesh.triangles.size() * 3u);
        std::size_t triangle_index = 0u;
        for (const Triangle& triangle : mesh.triangles)
        {
            if ((triangle_index++ % 4096u) == 0u && stop_token.stop_requested())
            {
                throw CollisionError("Terrain mapping was canceled.");
            }
            if (triangle.a >= mesh.vertices.size()
                || triangle.b >= mesh.vertices.size()
                || triangle.c >= mesh.vertices.size())
            {
                throw CollisionError("Recast input contains an invalid triangle.");
            }
            triangles.insert(triangles.end(), {
                static_cast<int>(triangle.a),
                static_cast<int>(triangle.b),
                static_cast<int>(triangle.c),
            });
        }

        partitioned.PartitionMesh(
            vertices.data(),
            triangles.data(),
            static_cast<int>(mesh.triangles.size()),
            256);
        if (partitioned.tris.empty())
        {
            throw CollisionError("Recast spatial mesh partition failed.");
        }
        if (stop_token.stop_requested())
        {
            throw CollisionError("Terrain mapping was canceled.");
        }

        int grid_width = 0;
        int grid_height = 0;
        rcCalcGridSize(minimum, maximum, cell_size, &grid_width, &grid_height);
        const int tile_width = (grid_width + tile_size - 1) / tile_size;
        const int tile_height = (grid_height + tile_size - 1) / tile_size;
        if (tile_width <= 0 || tile_height <= 0
            || static_cast<std::uint64_t>(tile_width) * tile_height > 16384u)
        {
            throw CollisionError("Recast tile dimensions are invalid.");
        }

        const unsigned int tile_count = static_cast<unsigned int>(tile_width * tile_height);
        const unsigned int tile_bits = std::min(integer_log2(next_power_of_two(tile_count)), 14u);
        const unsigned int poly_bits = 22u - tile_bits;

        nav_mesh.reset(dtAllocNavMesh());
        if (nav_mesh == nullptr)
        {
            throw CollisionError("Detour navmesh allocation failed.");
        }
        dtNavMeshParams nav_params{};
        rcVcopy(nav_params.orig, minimum);
        nav_params.tileWidth = static_cast<float>(tile_size) * cell_size;
        nav_params.tileHeight = static_cast<float>(tile_size) * cell_size;
        nav_params.maxTiles = 1 << tile_bits;
        nav_params.maxPolys = 1 << poly_bits;
        if (dtStatusFailed(nav_mesh->init(&nav_params)))
        {
            throw CollisionError("Detour navmesh initialization failed.");
        }

        rcContext context(false);
        std::size_t built_tiles = 0u;
        for (int y = 0; y < tile_height; ++y)
        {
            for (int x = 0; x < tile_width; ++x)
            {
                if (stop_token.stop_requested())
                {
                    throw CollisionError("Terrain mapping was canceled.");
                }
                float tile_minimum[3]{
                    minimum[0] + static_cast<float>(x * tile_size) * cell_size,
                    minimum[1],
                    minimum[2] + static_cast<float>(y * tile_size) * cell_size,
                };
                float tile_maximum[3]{
                    minimum[0] + static_cast<float>((x + 1) * tile_size) * cell_size,
                    maximum[1],
                    minimum[2] + static_cast<float>((y + 1) * tile_size) * cell_size,
                };
                TileBuildResult tile = build_tile(
                    context,
                    vertices,
                    partitioned,
                    x,
                    y,
                    tile_minimum,
                    tile_maximum);
                if (stop_token.stop_requested())
                {
                    if (tile.data != nullptr)
                    {
                        dtFree(tile.data);
                    }
                    throw CollisionError("Terrain mapping was canceled.");
                }
                if (tile.data == nullptr)
                {
                    continue;
                }
                const dtStatus status = nav_mesh->addTile(
                    tile.data,
                    tile.size,
                    DT_TILE_FREE_DATA,
                    0,
                    nullptr);
                if (dtStatusFailed(status))
                {
                    dtFree(tile.data);
                    throw CollisionError("Detour rejected a generated navigation tile.");
                }
                ++built_tiles;
            }
        }
        if (built_tiles == 0u)
        {
            throw CollisionError("Recast generated no walkable navigation tiles.");
        }

        nav_query.reset(dtAllocNavMeshQuery());
        if (nav_query == nullptr || dtStatusFailed(nav_query->init(nav_mesh.get(), 32768)))
        {
            throw CollisionError("Detour query initialization failed.");
        }
        filter.setIncludeFlags(walk_flag);
        filter.setExcludeFlags(0u);
    }

    const CollisionWorld* collision_world;
    bool allow_long_step_segments;
    bool reject_excessive_local_detours;
    NavMeshPointer nav_mesh;
    NavQueryPointer nav_query;
    dtQueryFilter filter;
    mutable std::mutex query_mutex;
};

RecastZone::RecastZone(
    const ParsedZoneMesh& mesh,
    const CollisionWorld& collision_world,
    const std::stop_token stop_token)
    : impl_(std::make_unique<Impl>(mesh, collision_world, stop_token))
{
}

RecastZone::~RecastZone() = default;
RecastZone::RecastZone(RecastZone&&) noexcept = default;
RecastZone& RecastZone::operator=(RecastZone&&) noexcept = default;

const std::string& RecastZone::settings_digest()
{
    static const std::string digest = "de3351ac99f62503c219ea5c3b53ecbc97ba23b503b9f8a0b62e7c29aeaa10a1";
    return digest;
}

PathResult RecastZone::find_path(
    const Vec3& start,
    const Vec3& destination,
    const float arrival_radius,
    const std::size_t maximum_points) const
{
    if (!finite_vec3(start) || !finite_vec3(destination)
        || !std::isfinite(arrival_radius)
        || arrival_radius < 0.0f
        || arrival_radius > 100.0f
        || maximum_points < 2u
        || maximum_points > 4096u)
    {
        throw CollisionError("Path query input is invalid.");
    }

    const std::lock_guard<std::mutex> query_lock(impl_->query_mutex);

    PathResult unreachable;
    unreachable.settings_digest = settings_digest();
    unreachable.reason = "No collision-safe route reaches the destination.";

    const float start_position[3]{start.x, start.y, start.z};
    const float start_extents[3]{8.0f, 8.0f, 8.0f};
    dtPolyRef start_reference = 0;
    float projected_start[3]{};
    if (dtStatusFailed(impl_->nav_query->findNearestPoly(
            start_position,
            start_extents,
            &impl_->filter,
            &start_reference,
            projected_start))
        || start_reference == 0)
    {
        unreachable.reason = "The player is outside the generated walkable terrain.";
        return unreachable;
    }

    std::vector<Vec3> destination_samples;
    destination_samples.push_back(destination);
    constexpr int angle_count = 16;
    for (int ring = 1; ring <= 4; ++ring)
    {
        const float radius = arrival_radius * static_cast<float>(ring) / 4.0f;
        for (int angle = 0; angle < angle_count; ++angle)
        {
            const float radians = static_cast<float>(2.0 * std::numbers::pi)
                * static_cast<float>(angle)
                / static_cast<float>(angle_count);
            destination_samples.push_back(Vec3{
                destination.x + std::cos(radians) * radius,
                destination.y,
                destination.z + std::sin(radians) * radius,
            });
        }
    }

    PathResult best = unreachable;
    std::vector<dtPolyRef> polygon_path(8192u);
    bool found_end_polygon = false;
    bool found_complete_corridor = false;
    bool found_straight_path = false;
    bool rejected_by_capsule = false;
    std::string first_capsule_failure;
    for (const Vec3& sample : destination_samples)
    {
        const float candidate_position[3]{sample.x, sample.y, sample.z};
        const float end_extents[3]{1.5f, 5.0f, 1.5f};
        dtPolyRef end_reference = 0;
        float projected_end[3]{};
        if (dtStatusFailed(impl_->nav_query->findNearestPoly(
                candidate_position,
                end_extents,
                &impl_->filter,
                &end_reference,
                projected_end))
            || end_reference == 0)
        {
            continue;
        }
        const Vec3 end_point{projected_end[0], projected_end[1], projected_end[2]};
        if (horizontal_distance(end_point, destination) > arrival_radius + 0.05f)
        {
            continue;
        }
        found_end_polygon = true;

        PolyFlagGuard disabled_polygons(impl_->nav_mesh.get());
        for (int attempt = 0; attempt < 96; ++attempt)
        {
            int polygon_count = 0;
            const dtStatus path_status = impl_->nav_query->findPath(
                start_reference,
                end_reference,
                projected_start,
                projected_end,
                &impl_->filter,
                polygon_path.data(),
                &polygon_count,
                static_cast<int>(polygon_path.size()));
            if (dtStatusFailed(path_status)
                || dtStatusDetail(path_status, DT_BUFFER_TOO_SMALL)
                || polygon_count <= 0
                || polygon_path[static_cast<std::size_t>(polygon_count - 1)] != end_reference)
            {
                break;
            }
            found_complete_corridor = true;

            std::vector<Vec3> waypoints;
            std::vector<dtPolyRef> waypoint_references;
            waypoints.reserve(static_cast<std::size_t>(polygon_count) + 1u);
            waypoint_references.reserve(static_cast<std::size_t>(polygon_count) + 1u);
            waypoints.push_back(Vec3{projected_start[0], projected_start[1], projected_start[2]});
            waypoint_references.push_back(start_reference);
            bool centers_valid = true;
            for (int index = 1; index + 1 < polygon_count; ++index)
            {
                Vec3 center;
                if (!polygon_center(
                        impl_->nav_mesh.get(),
                        impl_->nav_query.get(),
                        polygon_path[static_cast<std::size_t>(index)],
                        center))
                {
                    centers_valid = false;
                    break;
                }
                if (distance(waypoints.back(), center) >= 0.01f)
                {
                    waypoints.push_back(center);
                    waypoint_references.push_back(polygon_path[static_cast<std::size_t>(index)]);
                }
            }
            const Vec3 final_point{projected_end[0], projected_end[1], projected_end[2]};
            if (centers_valid && distance(waypoints.back(), final_point) >= 0.01f)
            {
                waypoints.push_back(final_point);
                waypoint_references.push_back(end_reference);
            }
            if (!centers_valid || waypoints.size() < 2u)
            {
                break;
            }

            std::vector<Vec3> simplified_points;
            std::vector<dtPolyRef> simplified_references;
            simplified_points.reserve(waypoints.size());
            simplified_references.reserve(waypoint_references.size());
            simplified_points.push_back(waypoints.front());
            simplified_references.push_back(waypoint_references.front());
            std::size_t current = 0u;
            while (current + 1u < waypoints.size())
            {
                const std::size_t farthest = std::min(waypoints.size() - 1u, current + 24u);
                std::size_t selected = current + 1u;
                for (std::size_t candidate_index = farthest;
                     candidate_index > current + 1u;
                     --candidate_index)
                {
                    bool follows_height = true;
                    for (std::size_t middle = current + 1u; middle < candidate_index; ++middle)
                    {
                        const float fraction = static_cast<float>(middle - current)
                            / static_cast<float>(candidate_index - current);
                        const float interpolated_y = waypoints[current].y
                            + (waypoints[candidate_index].y - waypoints[current].y) * fraction;
                        if (std::fabs(waypoints[middle].y - interpolated_y) > agent_max_climb)
                        {
                            follows_height = false;
                            break;
                        }
                    }
                    if (!follows_height)
                    {
                        continue;
                    }

                    const float ray_start[3]{
                        waypoints[current].x,
                        waypoints[current].y,
                        waypoints[current].z,
                    };
                    const float ray_end[3]{
                        waypoints[candidate_index].x,
                        waypoints[candidate_index].y,
                        waypoints[candidate_index].z,
                    };
                    float hit_fraction = 0.0f;
                    float hit_normal[3]{};
                    std::array<dtPolyRef, 64> ray_path{};
                    int ray_path_count = 0;
                    const dtStatus ray_status = impl_->nav_query->raycast(
                        waypoint_references[current],
                        ray_start,
                        ray_end,
                        &impl_->filter,
                        &hit_fraction,
                        hit_normal,
                        ray_path.data(),
                        &ray_path_count,
                        static_cast<int>(ray_path.size()));
                    if (dtStatusFailed(ray_status)
                        || dtStatusDetail(ray_status, DT_BUFFER_TOO_SMALL)
                        || hit_fraction < 0.999f
                        || !traversable_capsule_segment(
                            *impl_->collision_world,
                            waypoints[current],
                            waypoints[candidate_index],
                            impl_->allow_long_step_segments))
                    {
                        continue;
                    }
                    selected = candidate_index;
                    break;
                }
                simplified_points.push_back(waypoints[selected]);
                simplified_references.push_back(waypoint_references[selected]);
                current = selected;
            }
            waypoints = std::move(simplified_points);
            waypoint_references = std::move(simplified_references);
            if (waypoints.size() > maximum_points)
            {
                break;
            }
            found_straight_path = true;

            PathResult candidate;
            candidate.status = PathStatus::ready;
            candidate.projected_start = Vec3{projected_start[0], projected_start[1], projected_start[2]};
            candidate.projected_end = end_point;
            candidate.settings_digest = settings_digest();
            candidate.reason.clear();
            candidate.points.reserve(waypoints.size());
            bool clear = true;
            int failed_waypoint_index = -1;
            for (std::size_t index = 0; index < waypoints.size(); ++index)
            {
                const Vec3 point = waypoints[index];
                if (!candidate.points.empty() && distance(candidate.points.back(), point) < 0.01f)
                {
                    continue;
                }
                if (!candidate.points.empty())
                {
                    const SweepResult sweep = impl_->collision_world->sweep_capsule(
                        candidate.points.back(),
                        point,
                        agent_radius,
                        agent_height);
                    if (!sweep.clear && !traversable_capsule_segment(
                            *impl_->collision_world,
                            candidate.points.back(),
                            point,
                            impl_->allow_long_step_segments))
                    {
                        rejected_by_capsule = true;
                        failed_waypoint_index = static_cast<int>(index);
                        if (first_capsule_failure.empty())
                        {
                            first_capsule_failure = " segment "
                                + std::to_string(candidate.points.back().x) + ","
                                + std::to_string(candidate.points.back().y) + ","
                                + std::to_string(candidate.points.back().z) + " to "
                                + std::to_string(point.x) + ","
                                + std::to_string(point.y) + ","
                                + std::to_string(point.z) + " hit normal "
                                + std::to_string(sweep.normal.x) + ","
                                + std::to_string(sweep.normal.y) + ","
                                + std::to_string(sweep.normal.z)
                                + " fraction " + std::to_string(sweep.fraction)
                                + " point " + std::to_string(sweep.point.x) + ","
                                + std::to_string(sweep.point.y) + ","
                                + std::to_string(sweep.point.z)
                                + " triangle " + std::to_string(sweep.triangle_index)
                                + " at polygon-center index " + std::to_string(index)
                                + " of " + std::to_string(waypoints.size())
                                + ", refs "
                                + std::to_string(index > 0 ? waypoint_references[index - 1u] : 0)
                                + "/"
                                + std::to_string(waypoint_references[index])
                                + ", corridor " + std::to_string(polygon_count)
                                + ", attempt " + std::to_string(attempt) + ".";
                        }
                        clear = false;
                        break;
                    }
                    candidate.total_length += distance(candidate.points.back(), point);
                }
                candidate.points.push_back(point);
            }
            if (clear && candidate.points.size() >= 2u)
            {
                best = std::move(candidate);
                break;
            }
            if (failed_waypoint_index < 0)
            {
                break;
            }

            dtPolyRef rejected_reference = 0;
            const std::array<int, 4> reference_candidates{
                failed_waypoint_index,
                failed_waypoint_index - 1,
                failed_waypoint_index + 1,
                failed_waypoint_index - 2,
            };
            for (const int index : reference_candidates)
            {
                if (index < 0 || index >= static_cast<int>(waypoint_references.size()))
                {
                    continue;
                }
                const dtPolyRef reference = waypoint_references[static_cast<std::size_t>(index)];
                if (reference != 0 && reference != start_reference && reference != end_reference)
                {
                    rejected_reference = reference;
                    if (disabled_polygons.disable(rejected_reference))
                    {
                        break;
                    }
                    rejected_reference = 0;
                }
            }
            if (rejected_reference == 0)
            {
                break;
            }
        }
        if (best.status == PathStatus::ready)
        {
            break;
        }
    }
    if (best.status != PathStatus::ready)
    {
        if (!found_end_polygon)
        {
            best.reason = "The destination is outside the generated walkable terrain.";
        }
        else if (!found_complete_corridor)
        {
            best.reason = "The generated walkable terrain has no connected corridor.";
        }
        else if (!found_straight_path)
        {
            best.reason = "Detour could not extract a bounded waypoint path.";
        }
        else if (rejected_by_capsule)
        {
            best.reason = "Every generated corridor failed the player-sized collision check."
                + first_capsule_failure;
        }
    }
    return best;
}

} // namespace accessxi::collision
