group = "com.layrz.layrz_push"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

jacoco {
    toolVersion = "0.8.11"
}

plugins {
    id("com.android.library")
    id("kotlin-android")
    jacoco
}

android {
    namespace = "com.layrz.layrz_push"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = false
    }

    sourceSets {
        getByName("main") {
            kotlin.srcDirs("src/main/kotlin")
            java.srcDirs("src/main/java-disabled")
        }
        getByName("test") {
            kotlin.srcDirs("src/test/kotlin")
            java.srcDirs("src/test/java-disabled")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }

                // Robolectric JaCoCo configuration for coverage reports
                it.extensions.configure<JacocoTaskExtension> {
                    isIncludeNoLocationClasses = true
                    excludes = listOf("jdk.internal.*")
                }
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
    implementation("com.google.firebase:firebase-messaging:25.0.1")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.junit.vintage:junit-vintage-engine:5.10.2")
}

// JaCoCo coverage reporting task for unit tests
tasks.register<JacocoReport>("jacocoDebugReport") {
    dependsOn("testDebugUnitTest")

    reports {
        xml.required = true
        xml.outputLocation = layout.buildDirectory.file("reports/jacoco/jacoco.xml")
        html.required = true
        html.outputLocation = layout.buildDirectory.dir("reports/jacoco/html")
    }

    classDirectories.setFrom(
        fileTree(layout.buildDirectory.dir("tmp/kotlin-classes/debug")) {
            // Exclude Pigeon-generated code
            exclude("**/LayrzPush.g*")
        }
    )

    sourceDirectories.setFrom(files("src/main/kotlin"))
    executionData.setFrom(layout.buildDirectory.file("jacoco/testDebugUnitTest.exec"))
}

