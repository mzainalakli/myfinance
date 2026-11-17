import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// applicationId = identitas internal Android. JANGAN DIUBAH setelah rilis pertama.
// Nama tampilan ada di res/values/strings.xml (app_name), bukan di sini.
val appIdentity = "app.myfinance"

// Penandatanganan rilis: android/key.properties (dibuat oleh CI; tidak di-commit).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile") != null

android {
    // namespace = paket kode (Kotlin/R).
    namespace = "app.myfinance"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = appIdentity
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // versionName/versionCode: dari pubspec.yaml atau --build-name / --build-number.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_id", appIdentity)
    }

    buildFeatures {
        resValues = true // dipakai untuk string app_id (shortcuts.xml)
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Tanpa key.properties (build lokal) jatuh ke debug signing agar `flutter run --release` jalan.
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
