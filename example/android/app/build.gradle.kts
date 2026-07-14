plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

flutter {
    source = "../.."
}

android {
    namespace = "com.example.flutter_barcode_scanner_sdk_example"
    compileSdkVersion(36)
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.flutter_barcode_scanner_sdk_example"
        minSdkVersion(24)
        targetSdkVersion(36)
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
