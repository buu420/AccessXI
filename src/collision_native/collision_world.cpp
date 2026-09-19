#include "collision_native/collision_world.h"
#include "collision_native/player_contact.h"

#include <btBulletCollisionCommon.h>
#include <BulletCollision/NarrowPhaseCollision/btRaycastCallback.h>

#include <cmath>
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <queue>
#include <utility>
#include <vector>

namespace accessxi::collision {
namespace {

constexpr btScalar support_normal_y = btScalar(0.55);

bool finite_vec3(const Vec3& value) noexcept
{
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z);
}

Vec3 copy_vector(const btVector3& value)
{
    return Vec3{
        static_cast<float>(value.x()),
        static_cast<float>(value.y()),
        static_cast<float>(value.z()),
    };
}

btTransform capsule_transform(const Vec3& feet, const float height)
{
    btTransform transform;
    transform.setIdentity();
    transform.setOrigin(btVector3(
        btScalar(feet.x),
        btScalar(feet.y + height * 0.5f),
        btScalar(feet.z)));
    return transform;
}

class StartContactCallback final : public btCollisionWorld::ContactResultCallback
{
public:
    explicit StartContactCallback(const btCollisionObject* capsule)
        : capsule_(capsule)
    {
    }

    btScalar addSingleResult(
        btManifoldPoint& contact,
        const btCollisionObjectWrapper* object0,
        int,
        int index0,
        const btCollisionObjectWrapper* object1,
        int,
        int index1) override
    {
        if (contact.getDistance() > btScalar(0.001))
        {
            return btScalar(0.0);
        }

        btVector3 normal = contact.m_normalWorldOnB;
        int triangle_index = index1;
        if (object0->getCollisionObject() != capsule_)
        {
            normal = -normal;
            triangle_index = index0;
        }
        if (normal.y() >= support_normal_y)
        {
            return btScalar(0.0);
        }

        blocked = true;
        hit_normal = normal;
        hit_point = contact.getPositionWorldOnB();
        this->triangle_index = triangle_index;
        return btScalar(0.0);
    }

    bool blocked = false;
    btVector3 hit_normal{0, 0, 0};
    btVector3 hit_point{0, 0, 0};
    int triangle_index = -1;

private:
    const btCollisionObject* capsule_;
};

class BlockingSweepCallback final : public btCollisionWorld::ClosestConvexResultCallback
{
public:
    BlockingSweepCallback(const btVector3& start, const btVector3& end)
        : btCollisionWorld::ClosestConvexResultCallback(start, end)
    {
    }

    btScalar addSingleResult(
        btCollisionWorld::LocalConvexResult& local_result,
        bool normal_in_world_space) override
    {
        btVector3 world_normal = local_result.m_hitNormalLocal;
        if (!normal_in_world_space)
        {
            world_normal = local_result.m_hitCollisionObject->getWorldTransform().getBasis()
                * local_result.m_hitNormalLocal;
        }
        if (world_normal.y() >= support_normal_y)
        {
            return btScalar(1.0);
        }
        if (local_result.m_hitFraction <= m_closestHitFraction)
        {
            triangle_index = local_result.m_localShapeInfo == nullptr
                ? -1
                : local_result.m_localShapeInfo->m_triangleIndex;
        }

        btCollisionWorld::LocalConvexResult world_result(
            local_result.m_hitCollisionObject,
            local_result.m_localShapeInfo,
            world_normal,
            local_result.m_hitPointLocal,
            local_result.m_hitFraction);
        return btCollisionWorld::ClosestConvexResultCallback::addSingleResult(world_result, true);
    }

    int triangle_index = -1;
};

class PlayerTriangleCallback final : public btTriangleCallback
{
public:
    void processTriangle(btVector3* points, int, int index) override
    {
        btVector3 normal = (points[1] - points[0]).cross(points[2] - points[0]);
        const btScalar length = normal.length();
        if (length <= btScalar(1.0e-7)) return;
        normal /= length;
        indices.push_back(index);
        triangles.push_back(PlayerContactTriangle{
            copy_vector(points[0]), copy_vector(points[1]),
            copy_vector(points[2]), copy_vector(normal)});
    }
    std::vector<PlayerContactTriangle> triangles;
    std::vector<int> indices;
};

float horizontal_distance(const Vec3& a, const Vec3& b)
{
    return std::hypot(a.x - b.x, a.z - b.z);
}

// Every charge point in this file is one of exactly two primitives: a floor cast
// or a body resolve. Charging anywhere else would make the allowance drift away
// from the cost it is meant to bound.
bool spend_work(ContactBudget* budget, std::uint64_t units = 1u)
{
    return budget == nullptr || budget->spend(units);
}

bool settle_player_point(Vec3& feet, const std::vector<PlayerContactTriangle>& triangles,
    ContactBudget* budget)
{
    if (!spend_work(budget)) return false;
    const Vec3 center{feet.x, feet.y + 0.5f, feet.z};
    const auto result = resolvePlayerContact(triangles, center);
    if (!result.resolved) return false;
    const Vec3 corrected{result.center.x, result.center.y - 0.5f, result.center.z};
    if (horizontal_distance(corrected, feet) > 0.5f
        || corrected.y - feet.y > 0.5f || corrected.y - feet.y < -0.1f)
        return false;
    feet = corrected;
    return true;
}

bool player_body_segment(const Vec3& a, const Vec3& b,
    const std::vector<PlayerContactTriangle>& triangles, ContactBudget* budget)
{
    const float distance = std::hypot(horizontal_distance(a, b), b.y - a.y);
    const int samples = std::max(1, static_cast<int>(std::ceil(distance / 0.15f)));
    for (int i = 0; i <= samples; ++i)
    {
        if (!spend_work(budget)) return false;
        const float t = static_cast<float>(i) / samples;
        const Vec3 center{a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t + 0.5f, a.z + (b.z - a.z) * t};
        const auto result = resolvePlayerContact(triangles, center);
        if (!result.resolved || horizontal_distance(center, result.center) > 0.08f
            || std::fabs(center.y - result.center.y) > 0.5f)
            return false;
    }
    return true;
}

} // namespace

// MEASURED, NOT CHOSEN.
//
// Instrumented against the installed Crawler's Nest DAT with
// ACCESSXI_CONTACT_WORK_TRACE=1:
//
//   entrance -> Exoray, 61 points, 718 yalms   43,360 units   (271 ms via the DLL)
//   synthetic gap detour, 3 points                 480 units
//   synthetic 2-yalm ledge, unreachable         10,960 units
//
// All 82 catalogued enemy camps passed from the reported entrance. With exact
// segment caching and bounded subdivision, the largest query cost 482,855 units
// and the slowest took 12.609 seconds. Allow more than twice that measured work
// for nearby start positions. The addon runs zone 197 queries in the background.
// Cost per unit depends on triangle density; this is not a wall-clock guarantee.
const std::uint64_t kPlayerContactQueryWorkUnits = 1000000ull;

struct CollisionWorld::Impl final
{
    explicit Impl(const ParsedZoneMesh& mesh)
    {
        static_assert(sizeof(btScalar) == sizeof(float));
        if (mesh.vertices.empty() || mesh.triangles.empty())
        {
            throw CollisionError("Collision world requires a nonempty triangle mesh.");
        }
        if (mesh.vertices.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())
            || mesh.triangles.size() > static_cast<std::size_t>(std::numeric_limits<int>::max()))
        {
            throw CollisionError("Collision mesh is too large for Bullet.");
        }

        vertices.reserve(mesh.vertices.size() * 3u);
        for (const Vec3& vertex : mesh.vertices)
        {
            if (!finite_vec3(vertex))
            {
                throw CollisionError("Collision mesh contains a nonfinite vertex.");
            }
            vertices.push_back(btScalar(vertex.x));
            vertices.push_back(btScalar(vertex.y));
            vertices.push_back(btScalar(vertex.z));
        }

        indices.reserve(mesh.triangles.size() * 3u);
        for (const Triangle& triangle : mesh.triangles)
        {
            if (triangle.a >= mesh.vertices.size()
                || triangle.b >= mesh.vertices.size()
                || triangle.c >= mesh.vertices.size()
                || triangle.a > static_cast<std::uint32_t>(std::numeric_limits<int>::max())
                || triangle.b > static_cast<std::uint32_t>(std::numeric_limits<int>::max())
                || triangle.c > static_cast<std::uint32_t>(std::numeric_limits<int>::max()))
            {
                throw CollisionError("Collision mesh triangle index is invalid.");
            }
            indices.push_back(static_cast<int>(triangle.a));
            indices.push_back(static_cast<int>(triangle.b));
            indices.push_back(static_cast<int>(triangle.c));
        }

        configuration = std::make_unique<btDefaultCollisionConfiguration>();
        dispatcher = std::make_unique<btCollisionDispatcher>(configuration.get());
        broadphase = std::make_unique<btDbvtBroadphase>();
        world = std::make_unique<btCollisionWorld>(dispatcher.get(), broadphase.get(), configuration.get());
        mesh_interface = std::make_unique<btTriangleIndexVertexArray>(
            static_cast<int>(mesh.triangles.size()),
            indices.data(),
            3 * static_cast<int>(sizeof(int)),
            static_cast<int>(mesh.vertices.size()),
            vertices.data(),
            3 * static_cast<int>(sizeof(btScalar)));
        mesh_shape = std::make_unique<btBvhTriangleMeshShape>(mesh_interface.get(), true, true);
        static_object = std::make_unique<btCollisionObject>();
        static_object->setCollisionShape(mesh_shape.get());
        static_object->setCollisionFlags(btCollisionObject::CF_STATIC_OBJECT);
        world->addCollisionObject(static_object.get());
    }

    ~Impl()
    {
        if (world != nullptr && static_object != nullptr)
        {
            world->removeCollisionObject(static_object.get());
        }
    }

    std::vector<btScalar> vertices;
    std::vector<int> indices;
    std::unique_ptr<btDefaultCollisionConfiguration> configuration;
    std::unique_ptr<btCollisionDispatcher> dispatcher;
    std::unique_ptr<btBroadphaseInterface> broadphase;
    std::unique_ptr<btCollisionWorld> world;
    std::unique_ptr<btTriangleIndexVertexArray> mesh_interface;
    std::unique_ptr<btBvhTriangleMeshShape> mesh_shape;
    std::unique_ptr<btCollisionObject> static_object;

    std::vector<PlayerContactTriangle> player_triangles(const Vec3& a, const Vec3& b) const
    {
        PlayerTriangleCallback callback;
        mesh_shape->processAllTriangles(&callback,
            btVector3(std::min(a.x, b.x) - 1.1f, std::min(a.y, b.y) - 2.0f,
                std::min(a.z, b.z) - 1.1f),
            btVector3(std::max(a.x, b.x) + 1.1f, std::max(a.y, b.y) + 3.0f,
                std::max(a.z, b.z) + 1.1f));
        std::vector<std::size_t> order(callback.triangles.size());
        for (std::size_t i = 0; i < order.size(); ++i) order[i] = i;
        std::sort(order.begin(), order.end(), [&](std::size_t left, std::size_t right) {
            return callback.indices[left] < callback.indices[right];
        });
        std::vector<PlayerContactTriangle> result;
        result.reserve(order.size());
        for (std::size_t index : order) result.push_back(callback.triangles[index]);
        return result;
    }
};

std::optional<Vec3> CollisionWorld::find_floor(const Vec3& feet, const float vertical_extent) const
{
    if (!finite_vec3(feet) || !std::isfinite(vertical_extent) || vertical_extent <= 0.0f)
    {
        throw CollisionError("Floor query input is invalid.");
    }
    const btVector3 start(feet.x, feet.y + vertical_extent, feet.z);
    const btVector3 end(feet.x, feet.y - vertical_extent, feet.z);
    btCollisionWorld::ClosestRayResultCallback result(start, end);
    result.m_flags |= btTriangleRaycastCallback::kF_FilterBackfaces;
    impl_->world->rayTest(start, end, result);
    if (!result.hasHit() || result.m_hitNormalWorld.y() <= btScalar(0))
    {
        return std::nullopt;
    }
    return copy_vector(result.m_hitPointWorld);
}

bool CollisionWorld::walk_segment_with(const Vec3& start, const Vec3& end,
    const std::vector<PlayerContactTriangle>& triangles, ContactBudget* budget) const
{
    if (!finite_vec3(start) || !finite_vec3(end)) return false;
    const float horizontal = horizontal_distance(start, end);
    if (horizontal > 256.0f) return false;
    const int samples = std::max(2, static_cast<int>(std::ceil(horizontal / 0.1f)));
    std::optional<Vec3> previous;
    for (int i = 0; i <= samples; ++i)
    {
        if (!spend_work(budget)) return false;
        const float t = static_cast<float>(i) / samples;
        const Vec3 expected{start.x + (end.x - start.x) * t,
            start.y + (end.y - start.y) * t, start.z + (end.z - start.z) * t};
        auto floor = find_floor(expected, 1.8f);
        if (!floor || !settle_player_point(*floor, triangles, budget)) return false;
        if (previous && (std::fabs(previous->y - floor->y) > 2.0f
            || !player_body_segment(*previous, *floor, triangles, budget))) return false;
        previous = floor;
    }
    return true;
}

bool CollisionWorld::player_walk_segment(
    const Vec3& start, const Vec3& end, ContactBudget* budget) const
{
    if (!finite_vec3(start) || !finite_vec3(end)) return false;
    if (horizontal_distance(start, end) > 256.0f) return false;
    return walk_segment_with(start, end, impl_->player_triangles(start, end), budget);
}

bool CollisionWorld::player_contact_segment(
    const Vec3& start, const Vec3& end, ContactBudget* budget) const
{
    // A settled body can overhang a floor edge during the client's correction.
    // This check is only for short links between independently settled grid
    // nodes. It cannot authorize a long suspended segment over a depression.
    if (!finite_vec3(start) || !finite_vec3(end)
        || horizontal_distance(start, end) > 0.75f || std::fabs(start.y - end.y) > 2.0f)
        return false;
    return contact_segment_with(start, end, impl_->player_triangles(start, end), budget);
}

bool CollisionWorld::contact_segment_with(const Vec3& start, const Vec3& end,
    const std::vector<PlayerContactTriangle>& triangles, ContactBudget* budget) const
{
    if (horizontal_distance(start, end) > 0.75f || std::fabs(start.y - end.y) > 2.0f)
    {
        return false;
    }
    if (!player_body_segment(start, end, triangles, budget)) return false;
    const int count = std::max(2, static_cast<int>(std::ceil(horizontal_distance(start, end) / 0.1f)));
    for (int i = 0; i <= count; ++i)
    {
        if (!spend_work(budget)) return false;
        const float t = static_cast<float>(i) / count;
        const Vec3 expected{start.x + (end.x - start.x) * t,
            start.y + (end.y - start.y) * t - 1.0f, start.z + (end.z - start.z) * t};
        if (!find_floor(expected, 1.5f)) return false;
    }
    return true;
}

std::vector<Vec3> CollisionWorld::player_local_detour(
    const Vec3& start, const Vec3& end, const std::size_t maximum_points,
    ContactBudget* budget) const
{
    // Search only the small failed seam. This cannot turn a missing corridor
    // into an unbounded straight-line fallback through the rest of the zone.
    if (!finite_vec3(start) || !finite_vec3(end) || maximum_points < 2
        || horizontal_distance(start, end) > 6.0f || std::fabs(start.y - end.y) > 4.0f)
        return {};
    constexpr float spacing = 0.1f;
    const float min_x = std::min(start.x, end.x) - 2.0f;
    const float min_z = std::min(start.z, end.z) - 2.0f;
    const int width = static_cast<int>(std::ceil((std::fabs(start.x - end.x) + 4.0f) / spacing)) + 1;
    const int height = static_cast<int>(std::ceil((std::fabs(start.z - end.z) + 4.0f) / spacing)) + 1;
    if (width > 128 || height > 128) return {};
    const float bottom = std::min(start.y, end.y) - 2.0f;
    const float top = std::max(start.y, end.y) + 2.0f;
    const auto triangles = impl_->player_triangles(
        Vec3{min_x, bottom, min_z},
        Vec3{min_x + width * spacing, top, min_z + height * spacing});
    struct Node { Vec3 position; float floor; int x; int z; int parent = -1; };
    std::vector<Node> nodes;
    std::vector<std::vector<int>> cells(static_cast<std::size_t>(width * height));
    for (int z = 0; z < height; ++z)
    {
        for (int x = 0; x < width; ++x)
        {
            float ceiling = top;
            for (int layer = 0; layer < 8 && ceiling > bottom; ++layer)
            {
                if (!spend_work(budget)) return {};
                auto floor = find_floor(Vec3{min_x + x * spacing,
                    (ceiling + bottom) * 0.5f, min_z + z * spacing}, (ceiling - bottom) * 0.5f);
                if (!floor) break;
                ceiling = floor->y - 0.03f;
                const float floor_y = floor->y;
                if (!settle_player_point(*floor, triangles, budget))
                {
                    if (budget != nullptr && budget->exhausted()) return {};
                    continue;
                }
                cells[static_cast<std::size_t>(z * width + x)].push_back(static_cast<int>(nodes.size()));
                nodes.push_back(Node{*floor, floor_y, x, z});
            }
        }
    }
    const auto nearest = [&](const Vec3& point) {
        int best = -1;
        float best_distance = 1.0f;
        for (std::size_t i = 0; i < nodes.size(); ++i)
        {
            const float score = horizontal_distance(point, nodes[i].position)
                + std::fabs(point.y - nodes[i].position.y);
            if (score < best_distance
                && walk_segment_with(point, nodes[i].position, triangles, budget))
            {
                best = static_cast<int>(i);
                best_distance = score;
            }
        }
        return best;
    };
    const int first = nearest(start), last = nearest(end);
    if (first < 0 || last < 0) return {};
    std::queue<int> pending;
    pending.push(first);
    nodes[first].parent = first;
    while (!pending.empty() && nodes[last].parent < 0)
    {
        if (budget != nullptr && budget->exhausted()) return {};
        const int current = pending.front(); pending.pop();
        const Node a = nodes[current];
        for (int dz = -1; dz <= 1; ++dz)
        {
            for (int dx = -1; dx <= 1; ++dx)
            {
                if (dx == 0 && dz == 0) continue;
                const int x = a.x + dx, z = a.z + dz;
                if (x < 0 || x >= width || z < 0 || z >= height) continue;
                for (const int next : cells[static_cast<std::size_t>(z * width + x)])
                {
                    Node& b = nodes[next];
                    if (b.parent >= 0 || std::fabs(a.floor - b.floor) > 2.0f
                        || !player_body_segment(a.position, b.position, triangles, budget)) continue;
                    b.parent = current;
                    pending.push(next);
                }
            }
        }
    }
    if (nodes[last].parent < 0) return {};
    std::vector<Vec3> reversed;
    for (int at = last;; at = nodes[at].parent)
    {
        reversed.push_back(nodes[at].position);
        if (at == first) break;
        if (reversed.size() > nodes.size()) return {};
    }
    std::reverse(reversed.begin(), reversed.end());
    reversed.insert(reversed.begin(), start);
    reversed.push_back(end);
    std::vector<Vec3> result{start};
    std::size_t current = 0;
    while (current + 1 < reversed.size())
    {
        std::size_t selected = current + 1;
        for (std::size_t candidate = reversed.size() - 1; candidate > current; --candidate)
        {
            if (walk_segment_with(reversed[current], reversed[candidate], triangles, budget))
            {
                selected = candidate;
                break;
            }
        }
        if (budget != nullptr && budget->exhausted()) return {};
        if (!walk_segment_with(result.back(), reversed[selected], triangles, budget)
            && !contact_segment_with(result.back(), reversed[selected], triangles, budget))
            return {};
        result.push_back(reversed[selected]);
        if (result.size() > maximum_points) return {};
        current = selected;
    }
    return result;
}

std::vector<Vec3> CollisionWorld::player_segment_detour(
    const Vec3& start, const Vec3& end, const std::size_t maximum_points,
    ContactBudget* budget) const
{
    if (!finite_vec3(start) || !finite_vec3(end) || maximum_points < 2) return {};
    const float horizontal = horizontal_distance(start, end);
    const float vertical = std::fabs(start.y - end.y);
    if (horizontal <= 6.0f && vertical <= 4.0f)
        return player_local_detour(start, end, maximum_points, budget);
    if (horizontal > 256.0f || vertical > 128.0f) return {};

    // A long or steep candidate may contain one small floor seam. Keep each
    // local search bounded instead of rejecting the whole candidate based on
    // the distance between its original waypoints. Every resulting subsegment
    // still requires the same ground/contact validation.
    const int sections = std::max(2, static_cast<int>(
        std::ceil(std::max(horizontal / 3.0f, vertical / 2.0f))));
    std::vector<Vec3> result{start};
    for (int i = 1; i <= sections; ++i)
    {
        if ((budget != nullptr && budget->exhausted()) || result.size() >= maximum_points)
            return {};
        const float t = static_cast<float>(i) / sections;
        const Vec3 point = i == sections ? end : Vec3{
            start.x + (end.x - start.x) * t,
            start.y + (end.y - start.y) * t,
            start.z + (end.z - start.z) * t};
        if (player_walk_segment(result.back(), point, budget))
        {
            result.push_back(point);
            continue;
        }
        const auto local = player_local_detour(
            result.back(), point, maximum_points - result.size() + 1u, budget);
        if (local.size() < 2u) return {};
        result.insert(result.end(), local.begin() + 1, local.end());
    }
    return result;
}

CollisionWorld::CollisionWorld(const ParsedZoneMesh& mesh)
    : impl_(std::make_unique<Impl>(mesh))
{
}

CollisionWorld::~CollisionWorld() = default;
CollisionWorld::CollisionWorld(CollisionWorld&&) noexcept = default;
CollisionWorld& CollisionWorld::operator=(CollisionWorld&&) noexcept = default;

SweepResult CollisionWorld::sweep_capsule(
    const Vec3& start_feet,
    const Vec3& end_feet,
    const float radius,
    const float height) const
{
    if (!finite_vec3(start_feet) || !finite_vec3(end_feet))
    {
        throw CollisionError("Capsule sweep coordinates must be finite.");
    }
    if (!std::isfinite(radius)
        || !std::isfinite(height)
        || radius <= 0.0f
        || height <= radius * 2.0f
        || radius > 10.0f
        || height > 20.0f)
    {
        throw CollisionError("Capsule sweep dimensions are invalid.");
    }

    btCapsuleShape capsule(btScalar(radius), btScalar(height - radius * 2.0f));
    const btTransform start_transform = capsule_transform(start_feet, height);
    const btTransform end_transform = capsule_transform(end_feet, height);

    btCollisionObject start_object;
    start_object.setCollisionShape(&capsule);
    start_object.setWorldTransform(start_transform);
    StartContactCallback start_callback(&start_object);
    impl_->world->contactTest(&start_object, start_callback);
    if (start_callback.blocked)
    {
        return SweepResult{
            false,
            0.0f,
            copy_vector(start_callback.hit_point),
            copy_vector(start_callback.hit_normal),
            start_callback.triangle_index,
        };
    }

    BlockingSweepCallback callback(start_transform.getOrigin(), end_transform.getOrigin());
    impl_->world->convexSweepTest(&capsule, start_transform, end_transform, callback, btScalar(0.0));
    if (!callback.hasHit())
    {
        return SweepResult{true, 1.0f, end_feet, Vec3{}, -1};
    }
    return SweepResult{
        false,
        static_cast<float>(callback.m_closestHitFraction),
        copy_vector(callback.m_hitPointWorld),
        copy_vector(callback.m_hitNormalWorld),
        callback.triangle_index,
    };
}

} // namespace accessxi::collision
