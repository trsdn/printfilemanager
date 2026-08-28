import PrintFileManagerCore
import SceneKit
import SwiftUI

struct PlateAndModelPreview: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let record: PrintFileRecord
    @State private var platePreviews: [PlatePreview] = []
    @State private var mesh: ThreeMFMesh?
    @State private var selection = "3d"
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if availableModes.count > 1 {
                Picker("Preview", selection: $selection) {
                    ForEach(availableModes, id: \.id) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.35))

                if isLoading {
                    ProgressView()
                } else if selection == "3d", let mesh {
                    ThreeMFScenePreview(mesh: mesh)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let preview = selectedPlatePreview {
                    ThumbnailView(data: preview.imageData)
                        .padding(8)
                } else {
                    ThumbnailView(data: viewModel.thumbnail(for: record))
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 280)
        }
        .task(id: record.id) {
            await loadPreviewAssets()
        }
    }

    private var availableModes: [PreviewMode] {
        var modes: [PreviewMode] = []
        if mesh != nil {
            modes.append(PreviewMode(id: "3d", title: "3D", systemImage: "cube"))
        }
        modes.append(contentsOf: platePreviews.map { preview in
            PreviewMode(id: "plate-\(preview.index)", title: preview.title, systemImage: "square.stack.3d.up")
        })
        return modes.isEmpty ? [PreviewMode(id: "preview", title: "Preview", systemImage: "photo")] : modes
    }

    private var selectedPlatePreview: PlatePreview? {
        guard selection.hasPrefix("plate-"), let index = Int(selection.dropFirst("plate-".count)) else {
            return nil
        }
        return platePreviews.first { $0.index == index }
    }

    private func loadPreviewAssets() async {
        isLoading = true
        let url = record.url
        let result = await Task.detached(priority: .userInitiated) {
            (
                PlatePreviewExtractor().previews(for: url),
                ThreeMFMeshExtractor().mesh(for: url)
            )
        }.value

        platePreviews = result.0
        mesh = result.1
        if result.1 != nil {
            selection = "3d"
        } else if let firstPlate = result.0.first {
            selection = "plate-\(firstPlate.index)"
        } else {
            selection = "preview"
        }
        isLoading = false
    }

    private struct PreviewMode {
        let id: String
        let title: String
        let systemImage: String
    }
}

struct ThreeMFScenePreview: View {
    let mesh: ThreeMFMesh

    var body: some View {
        SceneView(
            scene: Self.scene(for: mesh),
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
    }

    private static func scene(for mesh: ThreeMFMesh) -> SCNScene {
        let scene = SCNScene()
        let node = SCNNode(geometry: geometry(for: mesh))
        node.geometry?.firstMaterial?.diffuse.contents = NSColor.controlAccentColor
        node.geometry?.firstMaterial?.roughness.contents = 0.72
        node.geometry?.firstMaterial?.metalness.contents = 0.08
        scene.rootNode.addChildNode(node)

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 100
        camera.fieldOfView = 42
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.8, 6)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 650
        lightNode.position = SCNVector3(2, 4, 4)
        scene.rootNode.addChildNode(lightNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    private static func geometry(for mesh: ThreeMFMesh) -> SCNGeometry {
        let normalizedVertices = normalize(mesh.vertices)
        let source = SCNGeometrySource(vertices: normalizedVertices.map { SCNVector3($0.x, $0.y, $0.z) })
        let indices = mesh.triangles.flatMap { [$0.a, $0.b, $0.c] }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial = SCNMaterial()
        geometry.firstMaterial?.isDoubleSided = true
        return geometry
    }

    private static func normalize(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard let first = vertices.first else { return [] }
        var minPoint = first
        var maxPoint = first

        for vertex in vertices.dropFirst() {
            minPoint = SIMD3<Float>(min(minPoint.x, vertex.x), min(minPoint.y, vertex.y), min(minPoint.z, vertex.z))
            maxPoint = SIMD3<Float>(max(maxPoint.x, vertex.x), max(maxPoint.y, vertex.y), max(maxPoint.z, vertex.z))
        }

        let center = (minPoint + maxPoint) / 2
        let size = max(maxPoint.x - minPoint.x, max(maxPoint.y - minPoint.y, maxPoint.z - minPoint.z))
        let scale: Float = size > 0 ? 3.4 / size : 1

        return vertices.map { vertex in
            let centered = (vertex - center) * scale
            return SIMD3<Float>(centered.x, centered.z, -centered.y)
        }
    }
}
