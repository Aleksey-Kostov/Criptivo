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

// Force compileSdk 36 on every Android library/app plugin module
// (file_picker, flutter_webrtc, etc.)
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            androidExt.javaClass.methods
                .find { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(androidExt, 36)
            androidExt.javaClass.methods
                .find { it.name == "setCompileSdkVersion" && it.parameterCount == 1 }
                ?.invoke(androidExt, 36)
        } catch (_: Exception) {
            // ignore
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}