import com.android.build.gradle.LibraryExtension

group = "com.eventer.flutter_barcode_scanner_sdk"
version = "1.0-SNAPSHOT"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply(plugin = "com.android.library")

extensions.configure<LibraryExtension>("android") {
    namespace = "com.eventer.flutter_barcode_scanner_sdk"

    compileSdkVersion(36)

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdkVersion(24)
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

dependencies {
    add("implementation", "androidx.core:core-ktx:1.17.0")
    add("implementation", "androidx.camera:camera-core:1.4.2")
    add("implementation", "androidx.camera:camera-camera2:1.4.2")
    add("implementation", "androidx.camera:camera-lifecycle:1.4.2")
    add("implementation", "androidx.camera:camera-view:1.4.2")
    add("implementation", "com.google.mlkit:barcode-scanning:17.3.0")
    add("testImplementation", "org.jetbrains.kotlin:kotlin-test-junit5:2.3.20")
    add("testImplementation", "org.mockito:mockito-core:5.0.0")
}
