import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── 서명 키 로드 ────────────────────────────────────────────────
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

android {
    namespace = "com.example.store_traffic_booster"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // ── 서명 설정 ──────────────────────────────────────────────
    signingConfigs {
        create("release") {
            keyAlias      = keyProperties.getProperty("keyAlias")
            keyPassword   = keyProperties.getProperty("keyPassword")
            storeFile     = keyProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keyProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        applicationId = "com.storetrafficbooster.app"
        minSdk = flutter.minSdkVersion
        // Google Play 정책: 2026-11-01 부터 Android 16(API 36) 미만을 타겟팅한
        // 업데이트는 거부된다. compileSdk 는 Flutter 기본값이 이미 36이라
        // 이 값만 올리면 된다.
        //
        // 36 에서 달라지는 것 점검 결과:
        //   - edge-to-edge 강제: targetSdk 35 에서 Android 15 가 이미 강제하고 있어
        //     새로 생기는 문제가 아니다. 하단 바는 Material BottomNavigationBar 가
        //     시스템 제스처 영역을 자동으로 피한다
        //   - 큰 화면에서 화면 방향 고정 무시: 앱이 방향을 고정하지 않아 무관
        //   - 예측형 뒤로가기: 미션 화면이 이미 PopScope 를 쓴다
        targetSdk     = 36
        versionCode   = 43
        versionName   = "1.0.0"
    }

    buildTypes {
        release {
            signingConfig    = signingConfigs.getByName("release")
            isMinifyEnabled  = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
