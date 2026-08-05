plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mongui.florilegio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    lint {
        disable += "Instantiatable"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mongui.florilegio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("personal") {
            storeFile = rootProject.file("signing/personal.keystore").also {
                check(it.exists()) {
                    "signing/personal.keystore not found"
                }
            }
            storePassword = System.getenv("KEYSTORE_STORE_PASSWORD")
                ?: error("KEYSTORE_STORE_PASSWORD not set")
            keyAlias = System.getenv("KEYSTORE_KEY_ALIAS")
                ?: error("KEYSTORE_KEY_ALIAS not set")
            keyPassword = System.getenv("KEYSTORE_KEY_PASSWORD")
                ?: error("KEYSTORE_KEY_PASSWORD not set")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("personal")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
