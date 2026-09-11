import MLX
import Testing

/// MLX finds its Metal library by walking the bundles it is loaded into, and
/// picks up `Contents/Resources/mlx-swift_Cmlx.bundle` on its own. An earlier
/// build phase staged a second copy next to the executable, which broke
/// notarization: a `.metallib` is not a Mach-O, so codesign can only sign it
/// through extended attributes, and those do not survive being zipped.
///
/// This test runs in the app host, so it fails if that lookup ever stops
/// working and the copy is needed again.
@Test func mlxLoadsItsMetalLibraryFromTheAppBundle() {
    let values = MLXArray([1.0, 2.0, 3.0] as [Float])
    #expect((values + values).sum().item(Float.self) == 12.0)
}
