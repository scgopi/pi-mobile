pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "pi-mobile"
include(":pi-ai")
include(":pi-agent-core")
include(":pi-tools")
include(":pi-session")
include(":pi-extensions")
include(":pi-app")
