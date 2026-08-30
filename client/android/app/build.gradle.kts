import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Present only once `mise run decrypt-signing` has run, which needs the age key.
val signingCreds = rootProject.file("signing/key.properties").takeIf { it.exists() }?.let { file ->
    Properties().apply { file.inputStream().use { load(it) } }
}

android {
    namespace = "com.mongui.florilegio"
    // flutter_secure_storage 11 requires 37, higher than flutter.compileSdkVersion
    compileSdk = 37
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
        signingCreds?.let { creds ->
            create("personal") {
                storeFile = rootProject.file("signing/personal.keystore")
                storePassword = creds.getProperty("KEYSTORE_STORE_PASSWORD")
                keyAlias = creds.getProperty("KEYSTORE_KEY_ALIAS")
                keyPassword = creds.getProperty("KEYSTORE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("personal")
        }
    }
}

// Without this, a credentialless box would quietly emit an unsigned release APK.
gradle.taskGraph.whenReady {
    check(signingCreds != null || allTasks.none { it.name.endsWith("Release") }) {
        "release builds need signing credentials: run `mise run build:android:release`"
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
