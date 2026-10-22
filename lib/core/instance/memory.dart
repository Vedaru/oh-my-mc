/// The one heap range the launcher accepts, for both the global default and a
/// per-instance override.
///
/// Exported once because they were previously three constants that disagreed:
/// the sliders capped at 16384 while `AppSettings` validated to 65536, so a
/// per-instance value the settings file accepted could not be expressed in the
/// UI. Any new clamp must import from here rather than restating a number.
library;

/// Below this the JVM cannot reliably start any supported Minecraft version.
const int kMinMemoryMb = 512;

/// Above this is a typo or a unit mix-up (`-Xmx64G` on a 16 GiB machine fails to
/// reserve its heap). Not a hardware limit: a real 128 GiB workstation exists,
/// but nobody types the right number for one and gets it wrong here.
const int kMaxMemoryMb = 65536;

/// Clamps [mb] into [kMinMemoryMb]..[kMaxMemoryMb].
int clampMemoryMb(int mb) =>
    mb < kMinMemoryMb ? kMinMemoryMb : (mb > kMaxMemoryMb ? kMaxMemoryMb : mb);
