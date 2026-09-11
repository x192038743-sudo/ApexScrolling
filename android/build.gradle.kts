// 依赖仓库：默认优先国内镜像（部分网络下 maven.google.com 不可达），
// 若在可直连 Google Maven 的网络中构建，可在 gradle.properties 里
// 设置 apex.cnMirrors=false 走官方仓库。
val useCnMirrors: Boolean =
    (project.findProperty("apex.cnMirrors") ?: "true").toString().toBoolean()

allprojects {
    repositories {
        if (useCnMirrors) {
            maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
            maven { url = uri("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/") }
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
        }
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
