plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Glide 1.1.0: still signed with the debug key (design 3.8 / 7.2 item 13). A project
            // keystore, kept outside the repo, is needed before the app is distributed.
            // R8 shrinking is the Flutter Gradle plugin's release default.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Glide 1.1.0 (Agragamee, Oct-2026): the Kotlin compiler options moved here from the deprecated
// android.kotlinOptions block (KGP 2.2 / Flutter 3.47.7); same JVM 17 target as compileOptions.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
