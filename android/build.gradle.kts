import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

group = "com.eventer.flutter_barcode_scanner_sdk"
version = "1.0-SNAPSHOT"

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply(plugin = "com.android.library")

// AGP 9.0 removed support for applying the Kotlin Gradle Plugin — Kotlin is built in from
// that version on. Apps still on AGP 8 supply KGP themselves, so it only needs applying
// there. This is Flutter's documented built-in-Kotlin guard for plugin authors; the AGP and
// KGP buildscript classpaths are deliberately absent so the consuming app's versions win.
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
if (agpMajor < 9) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

extensions.configure<LibraryExtension>("android") {
    namespace = "com.eventer.flutter_barcode_scanner_sdk"

    compileSdk = 36

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
        minSdk = 24
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

extensions.configure(KotlinAndroidProjectExtension::class.java) {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    add("implementation", "androidx.core:core-ktx:1.17.0")
    add("implementation", "androidx.camera:camera-core:1.6.1")
    add("implementation", "androidx.camera:camera-camera2:1.6.1")
    add("implementation", "androidx.camera:camera-lifecycle:1.6.1")
    add("implementation", "androidx.camera:camera-view:1.6.1")
    add("implementation", "com.google.mlkit:barcode-scanning:17.3.0")
    add("testImplementation", "org.jetbrains.kotlin:kotlin-test-junit5:2.3.20")
    add("testImplementation", "org.mockito:mockito-core:5.0.0")
}
