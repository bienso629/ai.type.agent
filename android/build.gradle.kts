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

    val ensureMinCompileSdk: (Project) -> Unit = { p ->
        p.plugins.withId("com.android.library") {
            val androidExt = p.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val getCompileSdk = androidExt.javaClass.methods.firstOrNull {
                        it.name == "getCompileSdk" && it.parameterCount == 0
                    }
                    val currentSdk = (getCompileSdk?.invoke(androidExt) as? Number)?.toInt() ?: 0
                    if (currentSdk < 36) {
                        val setCompileSdk = androidExt.javaClass.methods.firstOrNull {
                            it.name == "setCompileSdk" && it.parameterCount == 1 &&
                                (it.parameterTypes[0] == Int::class.java || it.parameterTypes[0] == java.lang.Integer::class.java)
                        }
                        if (setCompileSdk != null) {
                            setCompileSdk.invoke(androidExt, 36)
                        } else {
                            val setCompileSdkVersion = androidExt.javaClass.methods.firstOrNull {
                                it.name == "compileSdkVersion" && it.parameterCount == 1 &&
                                    (it.parameterTypes[0] == Int::class.java || it.parameterTypes[0] == java.lang.Integer::class.java)
                            }
                            setCompileSdkVersion?.invoke(androidExt, 36)
                        }
                    }
                } catch (_: Exception) {}
            }
        }
    }
    if (project.state.executed) {
        ensureMinCompileSdk(project)
    } else {
        project.afterEvaluate { ensureMinCompileSdk(this) }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
