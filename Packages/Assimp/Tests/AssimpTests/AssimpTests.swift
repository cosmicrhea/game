import XCTest
import Assimp

final class AssimpTests: XCTestCase {

    func testFailingInitializer() {
        XCTAssertThrowsError(try AiScene(file: "<no useful path>"))
    }

    func testImportFormats() {
        XCTAssertTrue(Scene.canImportFileExtension("obj"))
        XCTAssertTrue(Scene.canImportFileExtension("dae"))
        XCTAssertTrue(Scene.canImportFileExtension("gltf"))
        XCTAssertFalse(Scene.canImportFileExtension("txt"))
        XCTAssertFalse(Scene.canImportFileExtension("psd"))

        XCTAssertGreaterThanOrEqual(Scene.importFileExtensions().count, 70)

        print(Scene.importFileExtensions())
    }

    func testExportFormats() {
        XCTAssertGreaterThanOrEqual(Scene.exportFileExtensions().count, 20)
    }

    func testLoadAiSceneDAE() throws {

        let fileURL = try Resource.load(.duck_dae)

        var scene: AiScene!
        XCTAssertNoThrow(scene = try AiScene(file: fileURL.path, flags: [.removeRedundantMaterials,
                                                                         .genSmoothNormals,
                                                                         .calcTangentSpace]))

        XCTAssertEqual(scene.flags, [])
        XCTAssertEqual(scene.numberOfMeshes, 1)
        XCTAssertEqual(scene.numberOfMaterials, 1)
        XCTAssertEqual(scene.numberOfAnimations, 0)
        XCTAssertEqual(scene.numberOfCameras, 1)
        XCTAssertEqual(scene.numberOfLights, 1)
        XCTAssertEqual(scene.numberOfTextures, 0)

        // Scene Graph

        XCTAssertEqual(scene.rootNode.numberOfMeshes, 0)
        XCTAssertEqual(scene.rootNode.meshes.count, 0)
        XCTAssertEqual(scene.rootNode.numberOfChildren, 3)
        XCTAssertEqual(scene.rootNode.children.count, 3)
        XCTAssertEqual(scene.rootNode.name, "VisualSceneNode")
        XCTAssertEqual(scene.rootNode.children[0].name, "LOD3sp")
        XCTAssertEqual(scene.rootNode.children[0].meshes, [0])
        XCTAssertEqual(scene.rootNode.children[0].numberOfMeshes, 1)
        XCTAssertEqual(scene.rootNode.children[0].numberOfChildren, 0)
        XCTAssertEqual(scene.rootNode.children[1].name, "camera1")
        XCTAssertEqual(scene.rootNode.children[1].meshes, [])
        XCTAssertEqual(scene.rootNode.children[1].numberOfMeshes, 0)
        XCTAssertEqual(scene.rootNode.children[1].numberOfChildren, 0)
        XCTAssertEqual(scene.rootNode.children[2].name, "directionalLight1")
        XCTAssertEqual(scene.rootNode.children[2].meshes, [])
        XCTAssertEqual(scene.rootNode.children[2].numberOfMeshes, 0)
        XCTAssertEqual(scene.rootNode.children[2].numberOfChildren, 0)

        // Mesh

        XCTAssertEqual(scene.meshes[0].name, "LOD3spShape-lib")
        XCTAssertEqual(scene.meshes[0].primitiveTypes, [.triangle, .polygon])
        XCTAssertEqual(scene.meshes[0].numberOfVertices, 8500)
        XCTAssertEqual(scene.meshes[0].vertices[0...2], [-23.9364, 11.5353, 30.6125])
        XCTAssertEqual(scene.meshes[0].vertices.count, 25500)
        XCTAssertEqual(scene.meshes[0].numberOfFaces, 2144)
        XCTAssertEqual(scene.meshes[0].numberOfBones, 0)
        XCTAssertEqual(scene.meshes[0].numberOfAnimatedMeshes, 0)
        XCTAssertEqual(scene.meshes[0].tangents.count, 25500)
        XCTAssertEqual(scene.meshes[0].bitangents.count, 25500)

        // Faces

        XCTAssertEqual(scene.meshes[0].numberOfFaces, 2144)
        XCTAssertEqual(scene.meshes[0].faces.count, 2144)
        XCTAssertEqual(scene.meshes[0].faces[0].numberOfIndices, 4)
        XCTAssertEqual(scene.meshes[0].faces[0].indices, [0, 1, 2, 3])

        // Materials

        XCTAssertEqual(scene.materials[0].numberOfProperties, 19)
        XCTAssertEqual(scene.materials[0].numberAllocated, 20)
        XCTAssertEqual(scene.materials[0].properties[0].key, "?mat.name")

        // Textures

        XCTAssertEqual(scene.textures.count, 0)
        XCTAssertEqual(scene.meshes[0].numberOfUVComponents.0, 2)
        XCTAssertEqual(scene.meshes[0].texCoords.0?.count, 25500)
        XCTAssertEqual(scene.meshes[0].texCoords.0?[0...2], [0.866606, 0.398924, 0.0])
        XCTAssertEqual(scene.meshes[0].texCoords.0?[3...5], [0.871384, 0.397619, 0.0])
        XCTAssertEqual(scene.meshes[0].texCoordsPacked.0?[0...1], [0.866606, 0.398924])
        XCTAssertEqual(scene.meshes[0].texCoordsPacked.0?[2...3], [0.871384, 0.397619])

        // Lights

        XCTAssertEqual(scene.lights[0].name, "directionalLight1")

        // Cameras

        XCTAssertEqual(scene.cameras.count, 1)

        // print(scene.materials.map { $0.debugDescription })

        XCTAssertEqual(scene.materials[0].getMaterialColor(.COLOR_DIFFUSE), SIMD4<Float>(1.0, 1.0, 1.0, 1.0))
        XCTAssertEqual(scene.materials[0].getMaterialString(.TEXTURE(.diffuse, 0)), "./duckCM.tga")
    }

    func testLoadAiSceneObj() throws {

        let fileURL = try Resource.load(.box_obj)

        let scene: AiScene = try AiScene(file: fileURL.path)

        XCTAssertEqual(scene.flags, [])
        XCTAssertEqual(scene.numberOfMeshes, 1)
        XCTAssertEqual(scene.numberOfMaterials, 2)
        XCTAssertEqual(scene.numberOfAnimations, 0)
        XCTAssertEqual(scene.numberOfCameras, 0)
        XCTAssertEqual(scene.numberOfLights, 0)
        XCTAssertEqual(scene.numberOfTextures, 0)

        // Scene Graph

        XCTAssertEqual(scene.rootNode.numberOfMeshes, 0)
        XCTAssertEqual(scene.rootNode.meshes.count, 0)
        XCTAssertEqual(scene.rootNode.numberOfChildren, 1)
        XCTAssertEqual(scene.rootNode.children.count, 1)
        XCTAssertEqual(scene.rootNode.name, "models_OBJ_box.obj.box.obj")
        XCTAssertEqual(scene.rootNode.children[0].name, "1")
        XCTAssertEqual(scene.rootNode.children[0].meshes, [0])
        XCTAssertEqual(scene.rootNode.children[0].numberOfMeshes, 1)
        XCTAssertEqual(scene.rootNode.children[0].numberOfChildren, 0)

        // Mesh

        XCTAssertEqual(scene.meshes[0].name, "1")
        XCTAssertEqual(scene.meshes[0].primitiveTypes, [.polygon])
        XCTAssertEqual(scene.meshes[0].numberOfVertices, 8 * 3)
        XCTAssertEqual(scene.meshes[0].vertices[0...2], [-0.5, 0.5, 0.5])
        XCTAssertEqual(scene.meshes[0].numberOfFaces, 6)
        XCTAssertEqual(scene.meshes[0].numberOfBones, 0)
        XCTAssertEqual(scene.meshes[0].numberOfAnimatedMeshes, 0)

        // Faces

        XCTAssertEqual(scene.meshes[0].numberOfFaces, 6)
        XCTAssertEqual(scene.meshes[0].faces.count, 6)
        XCTAssertEqual(scene.meshes[0].faces[0].numberOfIndices, 4)
        XCTAssertEqual(scene.meshes[0].faces[0].indices, [0, 1, 2, 3])

        // Materials

        XCTAssertEqual(scene.materials[0].numberOfProperties, 16)
        XCTAssertEqual(scene.materials[0].numberAllocated, 20)
        XCTAssertEqual(scene.materials[0].properties[0].key, "?mat.name")

        // Textures

        XCTAssertEqual(scene.textures.count, 0)
        XCTAssertEqual(scene.meshes[0].numberOfUVComponents.0, 0)
        XCTAssertEqual(scene.meshes[0].texCoords.0?.count, nil)

        // Lights

        XCTAssertEqual(scene.lights.count, 0)

        // Cameras

        XCTAssertEqual(scene.cameras.count, 0)
    }

    func testLoadAiScene3DS() throws {
        let fileURL = try Resource.load(.cubeDiffuseTextured_3ds)

        let scene: AiScene = try AiScene(file: fileURL.path)

        XCTAssertEqual(scene.flags, [])
        XCTAssertEqual(scene.numberOfMeshes, 1)
        XCTAssertEqual(scene.numberOfMaterials, 1)
        XCTAssertEqual(scene.numberOfAnimations, 0)
        XCTAssertEqual(scene.numberOfCameras, 0)
        XCTAssertEqual(scene.numberOfLights, 0)
        XCTAssertEqual(scene.numberOfTextures, 0)

        // Scene Graph

        XCTAssertEqual(scene.rootNode.numberOfMeshes, 0)
        XCTAssertEqual(scene.rootNode.meshes.count, 0)
        XCTAssertEqual(scene.rootNode.numberOfChildren, 1)
        XCTAssertEqual(scene.rootNode.children.count, 1)
        XCTAssertEqual(scene.rootNode.name, "<3DSRoot>")
        XCTAssertEqual(scene.rootNode.children[0].name, "Quader01")
        XCTAssertEqual(scene.rootNode.children[0].meshes, [0])
        XCTAssertEqual(scene.rootNode.children[0].numberOfMeshes, 1)
        XCTAssertEqual(scene.rootNode.children[0].numberOfChildren, 0)

        // Mesh

        XCTAssertEqual(scene.meshes[0].name, "0")
        XCTAssertEqual(scene.meshes[0].primitiveTypes, [.triangle])
        XCTAssertEqual(scene.meshes[0].numberOfVertices, 36)
        XCTAssertEqual(scene.meshes[0].vertices[0...2], [-25.0, -25.0, 0.0])
        XCTAssertEqual(scene.meshes[0].numberOfFaces, 12)
        XCTAssertEqual(scene.meshes[0].numberOfBones, 0)
        XCTAssertEqual(scene.meshes[0].numberOfAnimatedMeshes, 0)
        XCTAssertEqual(scene.meshes[0].vertices[0], -25.0)
        XCTAssertEqual(scene.meshes[0].vertices[1], -25.0)
        XCTAssertEqual(scene.meshes[0].vertices[2], 0.0)

        XCTAssertEqual(scene.meshes[0].vertices[105], -25.0)
        XCTAssertEqual(scene.meshes[0].vertices[106], 25.0)
        XCTAssertEqual(scene.meshes[0].vertices[107], 0.0)

        // Faces

        XCTAssertEqual(scene.meshes[0].numberOfFaces, 12)
        XCTAssertEqual(scene.meshes[0].faces.count, 12)
        XCTAssertEqual(scene.meshes[0].faces[0].numberOfIndices, 3)
        XCTAssertEqual(scene.meshes[0].faces[0].indices, [0, 1, 2])

        // Materials

        XCTAssertEqual(scene.materials[0].numberOfProperties, 13)
        XCTAssertEqual(scene.materials[0].numberAllocated, 20)
        XCTAssertEqual(scene.materials[0].properties[0].key, "?mat.name")

        // Textures

        XCTAssertEqual(scene.textures.count, 0)
        XCTAssertEqual(scene.meshes[0].numberOfUVComponents.0, 2)
        XCTAssertEqual(scene.meshes[0].texCoords.0?.count, 108)
        XCTAssertEqual(scene.meshes[0].texCoords.0?[0...2], [0.6936096, 0.30822724, 0.0])

        // Lights

        XCTAssertEqual(scene.lights.count, 0)

        // Cameras

        XCTAssertEqual(scene.cameras.count, 0)

        XCTAssertEqual(scene.materials[0].getMaterialColor(.COLOR_DIFFUSE), SIMD4<Float>(0.5882353, 0.5882353, 0.5882353, 1.0))
        XCTAssertEqual(scene.materials[0].getMaterialString(.TEXTURE(.diffuse, 0)), "TEST.PNG")

    }

    func testLoadAiSceneGLB() throws {
        let fileURL = try Resource.load(.damagedHelmet_glb)

        let scene: AiScene = try AiScene(file: fileURL.path)

        XCTAssertEqual(scene.flags, [])
        XCTAssertEqual(scene.numberOfMeshes, 1)
        XCTAssertEqual(scene.numberOfMaterials, 2)
        XCTAssertEqual(scene.numberOfAnimations, 0)
        XCTAssertEqual(scene.numberOfCameras, 0)
        XCTAssertEqual(scene.numberOfLights, 0)
        XCTAssertEqual(scene.numberOfTextures, 5)

        // Scene Graph

        XCTAssertEqual(scene.rootNode.numberOfMeshes, 1)
        XCTAssertEqual(scene.rootNode.meshes.count, 1)
        XCTAssertEqual(scene.rootNode.numberOfChildren, 0)
        XCTAssertEqual(scene.rootNode.children.count, 0)
        XCTAssertEqual(scene.rootNode.name, "node_damagedHelmet_-6514")
        // Mesh

        XCTAssertEqual(scene.meshes[0].name, "mesh_helmet_LP_13930damagedHelmet")
        XCTAssertEqual(scene.meshes[0].primitiveTypes, [.triangle])
        XCTAssertEqual(scene.meshes[0].numberOfVertices, 14556)
        XCTAssertEqual(scene.meshes[0].vertices[0...2], [-0.61199456, -0.030940875, 0.48309004])
        XCTAssertEqual(scene.meshes[0].numberOfFaces, 15452)
        XCTAssertEqual(scene.meshes[0].numberOfBones, 0)
        XCTAssertEqual(scene.meshes[0].numberOfAnimatedMeshes, 0)
        XCTAssertEqual(scene.meshes[0].vertices[0], -0.61199456)
        XCTAssertEqual(scene.meshes[0].vertices[1], -0.030940875)
        XCTAssertEqual(scene.meshes[0].vertices[2], 0.48309004)

        XCTAssertEqual(scene.meshes[0].vertices[105], -0.5812146)
        XCTAssertEqual(scene.meshes[0].vertices[106], -0.029344887)
        XCTAssertEqual(scene.meshes[0].vertices[107], 0.391574)

        // Faces

        XCTAssertEqual(scene.meshes[0].numberOfFaces, 15452)
        XCTAssertEqual(scene.meshes[0].faces.count, 15452)
        XCTAssertEqual(scene.meshes[0].faces[0].numberOfIndices, 3)
        XCTAssertEqual(scene.meshes[0].faces[0].indices, [0, 1, 2])

        // Materials

        XCTAssertEqual(scene.materials[0].numberOfProperties, 50)
        XCTAssertEqual(scene.materials[0].numberAllocated, 80)
        XCTAssertEqual(scene.materials[0].properties[0].key, "?mat.name")

        // Textures

        XCTAssertEqual(scene.textures.count, scene.numberOfTextures)
        XCTAssertEqual(scene.meshes[0].numberOfUVComponents.0, 2)
        XCTAssertEqual(scene.meshes[0].texCoords.0?.count, 43668)
        XCTAssertEqual(scene.meshes[0].texCoords.0?[0...2], [0.704686, -0.24560404, 0.0])

        XCTAssertEqual(scene.textures[0].filename, nil)
        XCTAssertEqual(scene.textures[0].achFormatHint, "jpg")
        XCTAssertEqual(scene.textures[0].width, 935629)
        XCTAssertEqual(scene.textures[0].height, 0)
        XCTAssertEqual(scene.textures[0].isCompressed, true)
        XCTAssertEqual(scene.textures[0].numberOfPixels, 233907)
        XCTAssertEqual(scene.textures[0].textureData.count, 935628)

        XCTAssertEqual(scene.textures[0].textureData[0], 255)
        XCTAssertEqual(scene.textures[0].textureData[1], 216)
        XCTAssertEqual(scene.textures[0].textureData[2], 255)
        XCTAssertEqual(scene.textures[0].textureData[3], 224)
        XCTAssertEqual(scene.textures[0].textureData[0], 255) // b 255
        XCTAssertEqual(scene.textures[0].textureData[1], 216) // g 216
        XCTAssertEqual(scene.textures[0].textureData[2], 255) // r 255
        XCTAssertEqual(scene.textures[0].textureData[3], 224) // a 224
        XCTAssertEqual(scene.textures[0].textureData[0], 255) // r 255
        XCTAssertEqual(scene.textures[0].textureData[1], 216) // g 216
        XCTAssertEqual(scene.textures[0].textureData[2], 255) // b 255
        XCTAssertEqual(scene.textures[0].textureData[3], 224) // a 224

        XCTAssertEqual(scene.textures[1].filename, nil)
        XCTAssertEqual(scene.textures[1].achFormatHint, "jpg")
        XCTAssertEqual(scene.textures[1].width, 1300661)
        XCTAssertEqual(scene.textures[1].height, 0)
        XCTAssertEqual(scene.textures[1].isCompressed, true)
        XCTAssertEqual(scene.textures[1].numberOfPixels, 325165)
        XCTAssertEqual(scene.textures[1].textureData.count, 1300660)
        XCTAssertEqual(scene.textures[1].textureData[0], 255)
        XCTAssertEqual(scene.textures[1].textureData[1], 216)
        XCTAssertEqual(scene.textures[1].textureData[2], 255)
        XCTAssertEqual(scene.textures[1].textureData[3], 224)
        XCTAssertEqual(scene.textures[1].textureData[0], 255) // b 255
        XCTAssertEqual(scene.textures[1].textureData[1], 216) // g 216
        XCTAssertEqual(scene.textures[1].textureData[2], 255) // r 255
        XCTAssertEqual(scene.textures[1].textureData[3], 224) // a 224
        XCTAssertEqual(scene.textures[1].textureData[0], 255) // r 255
        XCTAssertEqual(scene.textures[1].textureData[1], 216) // g 216
        XCTAssertEqual(scene.textures[1].textureData[2], 255) // b 255
        XCTAssertEqual(scene.textures[1].textureData[3], 224) // a 224

        // Lights

        XCTAssertEqual(scene.lights.count, 0)

        // Cameras

        XCTAssertEqual(scene.cameras.count, 0)
    }
}
