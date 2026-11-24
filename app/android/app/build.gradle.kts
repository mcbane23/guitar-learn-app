plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mcbane23.guitarlearn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // The id Android uses to recognise the app: keep it the same so new
        // APKs install as updates.
        applicationId = "com.bane23.guitar.learn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Every build (on CI and locally) is signed with the same debug key
        // from the repository, so a new APK installs over the old one.
        // Android refuses updates signed with a different key.
        getByName("debug") {
            storeFile = file("keystore/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // One build gives three APKs: a small one per CPU type (arm64-v8a for
    // phones and tablets, armeabi-v7a for 32-bit TVs such as the XGIMI) and
    // a "universal" one with both, which installs on every device and is
    // what the fixed link releases/latest/download/guitar-learn.apk serves.
    // All three share the same versionCode, so any of them installs as an
    // update over any other. (Flutter's own --split-per-abi would give each
    // CPU type a different versionCode, which would break the in-app updater.)
    // x86/x86_64 is left out: there are no such devices for this app.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }
    applicationVariants.all {
        val variantName = baseName
        outputs.all {
            val output = this as com.android.build.gradle.api.ApkVariantOutput
            val abi: String? = output.getFilter("ABI")
            // The universal APK keeps the name the Flutter tool expects
            // (app-release.apk); the others are app-arm64-v8a-release.apk etc.
            output.outputFileName = if (abi == null) "app-$variantName.apk" else "app-$abi-$variantName.apk"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider, used to hand a downloaded update to the installer.
    implementation("androidx.core:core-ktx:1.13.1")
}
