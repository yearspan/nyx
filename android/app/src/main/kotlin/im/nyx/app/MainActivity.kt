package im.nyx.app

import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint

import android.content.Context

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(getApplicationContext())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    // Prevent Flutter engine gets destroyed on back button close.
    // 使用 texture 渲染模式：后台切换到外部应用（如打开文件）再返回时，
    // SurfaceView 会被销毁重建导致 1~2 秒白屏，TextureView 内容常驻内存可避免。
    override fun createFlutterFragment(): FlutterFragment =
        super.createFlutterFragment().apply {
            arguments?.putBoolean("destroy_engine_with_fragment", false)
            arguments?.putString("render_mode", "texture")
        }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            return eng
        }

        // Make push services run in the same engine.
        // https://codeberg.org/UnifiedPush/flutter-connector/src/branch/main/unifiedpush_android/android/src/main/kotlin/org/unifiedpush/flutter/connector/UnifiedPushService.kt#L17-L32
        fun provideRunningEngine(context: Context): FlutterEngine {
            var eng = engine
            if (eng == null) {
                eng = provideEngine(context)
                eng.getLocalizationPlugin().sendLocalesToFlutter(
                    context.getResources().getConfiguration())
                eng.getDartExecutor().executeDartEntrypoint(
                    DartEntrypoint.createDefault())
            }
            return eng
        }
    }
}
