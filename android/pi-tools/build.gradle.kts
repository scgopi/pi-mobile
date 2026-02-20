plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.vanniktech.maven.publish")
}

android {
    namespace = "com.pimobile.tools"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
        targetSdk = 34
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }
}

mavenPublishing {
    publishToMavenCentral(com.vanniktech.maven.publish.SonatypeHost.CENTRAL_PORTAL, automaticRelease = true)
    signAllPublications()
    coordinates("io.github.scgopi", "pi-tools", "1.0.1")

    pom {
        name.set("PiTools")
        description.set("Built-in tools for file, database, HTTP, and media operations")
        url.set("https://github.com/scgopi/pi-mobile")
        licenses {
            license {
                name.set("The Apache License, Version 2.0")
                url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
            }
        }
        developers {
            developer {
                id.set("scgopi")
                name.set("scgopi")
                url.set("https://github.com/scgopi")
            }
        }
        scm {
            url.set("https://github.com/scgopi/pi-mobile")
            connection.set("scm:git:git://github.com/scgopi/pi-mobile.git")
            developerConnection.set("scm:git:ssh://git@github.com/scgopi/pi-mobile.git")
        }
    }
}

dependencies {
    implementation(project(":pi-agent-core"))
    implementation(project(":pi-ai"))
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.activity:activity-ktx:1.8.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation("io.mockk:mockk:1.13.8")
}
