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

// Force compileSdk 36 for plugins still on 34 (file_picker, lifecycle, etc.)
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { androidExt ->
            try {
                val setCompileSdk = androidExt.javaClass.methods.find {
                    it.name == "setCompileSdk" && it.parameterCount == 1
                }
                setCompileSdk?.invoke(androidExt, 36)
            } catch (_: Exception) {
                // ignore modules without mutable compileSdk
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}