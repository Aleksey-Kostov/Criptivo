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

// Force compileSdk 36 for plugins still on 34 (file_picker, etc.)
// Do NOT use afterEvaluate here — conflicts with evaluationDependsOn(":app").
subprojects {
    fun configureCompileSdk36() {
        extensions.findByName("android")?.let { androidExt ->
            try {
                androidExt.javaClass.methods
                    .find { it.name == "setCompileSdk" && it.parameterCount == 1 }
                    ?.invoke(androidExt, 36)
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    pluginManager.withPlugin("com.android.library") {
        configureCompileSdk36()
    }
    pluginManager.withPlugin("com.android.application") {
        configureCompileSdk36()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}