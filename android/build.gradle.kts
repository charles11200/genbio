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

// tflite_flutter's own inconsistent Java/Kotlin compile target is handled
// via kotlin.jvm.target.validation.mode in gradle.properties instead of
// here - every DSL-level override attempted from this file (compileOptions,
// KotlinCompile.jvmTarget, jvmToolchain) hit a Gradle property-finalization
// error, since tflite_flutter's own build.gradle already reads/finalizes
// these before a root subprojects{} block gets a chance to run.

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
