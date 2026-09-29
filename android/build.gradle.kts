allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// camera_android_camerax compiles against camera-core, whose API references
// androidx.concurrent.futures.CallbackToFutureAdapter; that class isn't pulled
// onto the plugin's own compile classpath, which fails release builds.
project(":camera_android_camerax") {
    afterEvaluate {
        dependencies {
            add("compileOnly", "androidx.concurrent:concurrent-futures:1.1.0")
        }
    }
}
