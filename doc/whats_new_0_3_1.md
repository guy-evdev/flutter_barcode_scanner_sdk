# What's new in 0.3.1

A build fix for Android apps on Android Gradle Plugin (AGP) 9. No API changes and no migration.

## Android build with `android.builtInKotlin=false`

On AGP 9, an app that opts out of built-in Kotlin with `android.builtInKotlin=false` (the value
`flutter create` writes) failed to build with:

```
Extension of type 'KotlinAndroidProjectExtension' does not exist
```

The plugin now applies the Kotlin plugin whenever Kotlin is not built in, so these setups build:

| Setup | Result |
| --- | --- |
| AGP 8.x with the Kotlin plugin | Builds |
| AGP 9, `android.builtInKotlin=true` | Builds |
| AGP 9, `android.builtInKotlin=false` | Builds (failed in 0.3.0) |

Apps need no changes. If you added a local workaround for this error, remove it after upgrading
to `^0.3.1`.

## Compatibility

Flutter 3.47 cannot build any Android app with `android.newDsl=true`: its Gradle plugin still relies
on the legacy AGP extension classes and fails on the app side, before this package's build script
runs. Keep `android.newDsl=false`, the default `flutter create` writes, until Flutter supports it.
This package's build script already uses the new-DSL `LibraryExtension`, but that is untested until
a Flutter release allows it.
