#include "collision_native/collision_world.h"

#include <btBulletCollisionCommon.h>

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
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

} // namespace

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
};

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
