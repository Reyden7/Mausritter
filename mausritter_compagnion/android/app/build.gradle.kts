// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Le plugin Flutter doit venir après Android + Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("android/key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.vorn.mausritter_compagnion"      // <- libre, pour le code
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.vorn.mousritter"        // <- ID **définitif Play Store**
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = 1                              // <- incrémente à chaque release
        versionName = "1.0.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    signingConfigs {
        // Config release lue depuis android/key.properties
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            } else {
                println("⚠️ android/key.properties introuvable : la release sera signée en debug si vous l’assignez ci-dessous.")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Pas de minify en debug
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = false
            // Utilise la vraie signature release
            signingConfig = signingConfigs.getByName("release")
            // (Optionnel) Shrink resources + Proguard si tu veux
            // isMinifyEnabled = true
            // isShrinkResources = true
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
