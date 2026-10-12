package __PACKAGE__

import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * Installed by setup.sh (the android/ folder is generated, not committed).
 *
 * - FlutterFragmentActivity: required by local_auth for fingerprint / face unlock.
 * - FLAG_SECURE (release builds): the app shows voter and election data, so Android must not
 *   capture it. The recent-apps preview is blank, and screenshots, screen recording and casting
 *   show black. Debug builds skip it so the app can be demoed and tested on emulators.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) {
            // Set before the first frame so no window is ever drawn without protection.
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Android 13+: also opt out of the recents snapshot explicitly.
                setRecentsScreenshotEnabled(false)
            }
        }
        super.onCreate(savedInstanceState)
    }
}
