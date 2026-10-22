
plugins {
    id("com.android.application")

    // Firebase configuration
    id("com.google.gms.google-services")

    // Flutter Gradle plugin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sosatechnologies.osdating"

    // Fix Android dependency compatibility warnings
    compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Required by flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.sosatechnologies.osdating"

        minSdk = flutter.minSdkVersion
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release builds must use a private upload key supplied through environment
    // variables. Never silently sign a Play release with the debug key.
    signingConfigs {
        create("release") {
            val storeFilePath = System.getenv("OS_UPLOAD_STORE_FILE")
            val storePasswordValue = System.getenv("OS_UPLOAD_STORE_PASSWORD")
            val keyAliasValue = System.getenv("OS_UPLOAD_KEY_ALIAS")
            val keyPasswordValue = System.getenv("OS_UPLOAD_KEY_PASSWORD")
            if (!storeFilePath.isNullOrBlank()) storeFile = file(storeFilePath)
            if (!storePasswordValue.isNullOrBlank()) storePassword = storePasswordValue
            if (!keyAliasValue.isNullOrBlank()) keyAlias = keyAliasValue
            if (!keyPasswordValue.isNullOrBlank()) keyPassword = keyPasswordValue
        }
    }

    buildTypes {
        release {
            // If upload-key variables are missing, Gradle does not fall back to
            // debug signing. Configure the four OS_UPLOAD_* variables before release.
            if (System.getenv("OS_UPLOAD_STORE_FILE").isNullOrBlank().not() &&
                System.getenv("OS_UPLOAD_STORE_PASSWORD").isNullOrBlank().not() &&
                System.getenv("OS_UPLOAD_KEY_ALIAS").isNullOrBlank().not() &&
                System.getenv("OS_UPLOAD_KEY_PASSWORD").isNullOrBlank().not()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Required by flutter_local_notifications
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.4"
    )
}

flutter {
    source = "../.."
}
