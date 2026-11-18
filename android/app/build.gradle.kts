plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "app.xrv.client"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "app.xrv.client"
        minSdk = 23
        targetSdk = 36
        versionCode = 20000
        versionName = "2.0.0"
        buildConfigField("String", "ENGINE_VERSION", "\"2.0.0\"")
        val abis = (findProperty("xrvAbis") as? String)
            ?.split(',')
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?: listOf("arm64-v8a")
        ndk { abiFilters += abis }
    }

    val releaseStore = System.getenv("XRV_KEYSTORE")
        ?: rootProject.file("xrv-release.jks").takeIf { it.exists() }?.absolutePath
    val releasePassword = System.getenv("XRV_KEYSTORE_PASSWORD")
    val releaseAlias = System.getenv("XRV_KEY_ALIAS") ?: "xrv"
    val releaseKeyPassword = System.getenv("XRV_KEY_PASSWORD") ?: releasePassword

    signingConfigs {
        if (releaseStore != null && releasePassword != null) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = releasePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    buildFeatures {
        buildConfig = true
        viewBinding = true
    }

    sourceSets {
        getByName("main").jniLibs.srcDirs("../generated")
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += setOf(
                "META-INF/*.version",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        abortOnError = true
        checkReleaseBuilds = true
        sarifOutput = layout.buildDirectory.file("reports/lint-results.sarif").get().asFile
    }

}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.register<Exec>("buildXrvArm64Engine") {
    workingDir = rootProject.projectDir
    commandLine("bash", "scripts/build-android-engine.sh", "arm64-v8a")
    environment("GO_BIN", System.getenv("GO_BIN") ?: "go")
}

tasks.named("preBuild").configure {
    dependsOn("buildXrvArm64Engine")
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.core:core:1.15.0")
    implementation("com.google.android.material:material:1.12.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
