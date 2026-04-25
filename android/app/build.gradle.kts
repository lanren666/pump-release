plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sporramom.pump"
    compileSdk = flutter.compileSdkVersion
    // ndkVersion = flutter.ndkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sporramom.pump"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk = flutter.minSdkVersion
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    packagingOptions {
        pickFirsts += "lib/*/libc++_shared.so" // 多个 AAR（Android Library）文件中存在此 .so 文件，请选择第一个
    }

    configurations.all {
        exclude(group = "com.thingclips.smart", module = "thingsmart-modularCampAnno")
    }

    dependencies {
        implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
        implementation("com.alibaba:fastjson:1.1.67.android")
        implementation("com.squareup.okhttp3:okhttp-urlconnection:3.14.9")
        
        // AndroidX Core for permission handling
        implementation("androidx.core:core-ktx:1.12.0")
        
        // Splash Screen API for Android 12+
        implementation("androidx.core:core-splashscreen:1.0.1")

        // App SDK 最新稳定安卓版：
        implementation("com.thingclips.smart:thingsmart:6.11.0")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
