// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // plus moderne que "kotlin-android"
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropsFile = rootProject.file("key.properties")
val keystoreProps = Properties().apply {
    if (!keystorePropsFile.exists()) {
        throw GradleException("key.properties introuvable. Créez android/key.properties (voir modèle).")
    }
    load(FileInputStream(keystorePropsFile))
}

android {
    namespace = "com.vorn.mausritter_compagnion"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.vorn.mousritter"  // ← ID final Play Store
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 1
        versionName = "1.0.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    signingConfigs {
        create("release") {
            val sf = keystoreProps["storeFile"]?.toString()
                ?: throw GradleException("storeFile manquant dans key.properties")
            val sp = keystoreProps["storePassword"]?.toString()
                ?: throw GradleException("storePassword manquant dans key.properties")
            val ka = keystoreProps["keyAlias"]?.toString()
                ?: throw GradleException("keyAlias manquant dans key.properties")
            val kp = keystoreProps["keyPassword"]?.toString()
                ?: throw GradleException("keyPassword manquant dans key.properties")

            // Chemin relatif depuis le module app
            storeFile = file(sf)
            storePassword = sp
            keyAlias = ka
            keyPassword = kp
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}
