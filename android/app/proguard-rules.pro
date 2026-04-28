# ─────────────────────────────────────────────────────────────────
# ProGuard / R8 규칙 — 스토어 트래픽 부스터
# ─────────────────────────────────────────────────────────────────

# ── Flutter ───────────────────────────────────────────────────────
# Flutter 엔진 및 플러그인 진입점 보존
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ── Supabase / OkHttp / Gson ──────────────────────────────────────
# Supabase Kotlin SDK가 내부적으로 사용하는 OkHttp, Gson 보존
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Supabase 리플렉션 대상 모델 클래스 보존
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ── Google Mobile Ads (AdMob) ─────────────────────────────────────
# AdMob SDK는 자체 consumer ProGuard 규칙을 포함하므로 추가 규칙 불필요.
# 아래는 혹시 누락 시 대비용 기본 규칙.
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-keep class com.google.ads.** { *; }

# ── Kotlin ────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Lazy {
    <fields>;
}

# ── 일반 Android ─────────────────────────────────────────────────
# Parcelable 구현체 보존
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# 직렬화 가능 클래스 보존
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
