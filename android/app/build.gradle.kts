plugins {
    id("com.android.application")

    // Flutter Gradle Plugin musi być zastosowany
    // po pluginie Androida.
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase / Google Services
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val uploadKeystoreFile = file("yovoice-upload-keystore.jks")
val uploadKeyPassword = providers.environmentVariable(
    "YOVOICE_UPLOAD_KEY_PASSWORD",
).orElse(
    providers.exec {
        commandLine(
            "security",
            "find-generic-password",
            "-a",
            "yovoice",
            "-s",
            "yovoice-upload-keystore",
            "-w",
        )
    }.standardOutput.asText.map(String::trim),
)

android {
    namespace = "app.yovoice"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires this (java.time/java.util.stream
        // backport for API levels below the ones that ship them natively).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "app.yovoice"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!uploadKeystoreFile.exists()) {
                throw GradleException(
                    "Missing android/app/yovoice-upload-keystore.jks. " +
                        "Restore the YO Voice upload key before building release.",
                )
            }
            keyAlias = "upload"
            keyPassword = uploadKeyPassword.get()
            storeFile = uploadKeystoreFile
            storePassword = uploadKeyPassword.get()
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
