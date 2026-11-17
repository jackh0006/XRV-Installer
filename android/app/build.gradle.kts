plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android { namespace = "app.xrv.client"; compileSdk = 36; ndkVersion = "28.2.13676358"
    defaultConfig { applicationId = "app.xrv.client"; minSdk = 23; targetSdk = 35; versionCode = 10204; versionName = "1.2.4"; ndk { abiFilters += "arm64-v8a" } }
    buildFeatures { buildConfig = true }
    buildTypes { release { isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") } }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }
    sourceSets { getByName("main").jniLibs.srcDirs("../../generated") }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

tasks.register<Exec>("buildXrvArm64Engine") {
    workingDir = rootProject.projectDir
    commandLine("bash", "scripts/build-android-engine.sh", "arm64-v8a")
}
tasks.named("preBuild").configure { dependsOn("buildXrvArm64Engine") }

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.core:core:1.15.0")
    testImplementation("junit:junit:4.13.2")
}
