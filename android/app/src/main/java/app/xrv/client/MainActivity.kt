package app.xrv.client

import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.content.res.Configuration
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private val ids = mutableListOf<EditText>()
    private lateinit var key: EditText
    private lateinit var port: EditText
    private lateinit var status: TextView
    private val store by lazy { SecureProfileStore(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val bg = if (dark) Color.rgb(9,17,31) else Color.rgb(247,249,252); val surface = if (dark) Color.rgb(17,29,49) else Color.WHITE; val primary = if (dark) Color.rgb(234,242,255) else Color.rgb(20,30,45); val muted = if (dark) Color.rgb(190,205,230) else Color.rgb(75,91,110)
        val scroll = ScrollView(this); val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(48, 56, 48, 48); setBackgroundColor(bg) }
        fun label(text: String) = TextView(this).apply { this.text = text; setTextColor(primary); textSize = 14f; setPadding(0, 22, 0, 8) }
        fun field(hint: String, secret: Boolean = false) = EditText(this).apply { this.hint = hint; setHintTextColor(muted); setTextColor(primary); setSingleLine(); inputType = if (secret) InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_CLASS_TEXT; setBackgroundColor(surface); setPadding(24,18,24,18) }
        body.addView(TextView(this).apply { text = "XRV"; textSize = 34f; setTextColor(Color.rgb(28,150,110)); setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        body.addView(TextView(this).apply { text = "Private SOCKS5 tunnel"; textSize = 16f; setTextColor(muted); setPadding(0, 4, 0, 14) })
        body.addView(label("DEPLOYMENT IDS · UP TO 4"))
        repeat(4) { n -> field("Deployment ID ${n + 1} (optional after the first)").also { ids += it; body.addView(it, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = 12 }) } }
        body.addView(label("TUNNEL KEY")); key = field("64-character hexadecimal key", true); body.addView(key)
        body.addView(label("LOCAL SOCKS5 PORT")); port = field("1080").apply { inputType = InputType.TYPE_CLASS_NUMBER; setText("1080") }; body.addView(port)
        val buttons = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(0, 30, 0, 8) }
        val connect = Button(this).apply { text = "Connect"; setOnClickListener { connect() } }
        val disconnect = Button(this).apply { text = "Disconnect"; setOnClickListener { stopService(Intent(this@MainActivity, TunnelService::class.java)); status.text = "Disconnected" } }
        buttons.addView(connect, LinearLayout.LayoutParams(0, -2, 1f)); buttons.addView(disconnect, LinearLayout.LayoutParams(0, -2, 1f)); body.addView(buttons)
        body.addView(Button(this).apply { text = "About & donate"; setOnClickListener { startActivity(Intent(this@MainActivity, DonateActivity::class.java)) } })
        status = TextView(this).apply { setTextColor(muted); text = "Configure XRV, then connect. Apps can use SOCKS5 127.0.0.1:1080."; setPadding(0, 18, 0, 0) }; body.addView(status)
        body.addView(TextView(this).apply { text = "Security: configuration is encrypted locally with Android Keystore. XRV never logs the tunnel key. Do not enable a LAN listener."; setTextColor(muted); textSize = 12f; setPadding(0, 26, 0, 0) })
        scroll.addView(body); setContentView(scroll); restore()
    }
    private fun restore() { store.load()?.let { p -> p.deployments.forEachIndexed { i, v -> ids[i].setText(v) }; key.setText(p.tunnelKey); port.setText(p.socksPort.toString()) } }
    private fun connect() {
        val deployments = ids.map { it.text.toString().trim() }.filter { it.isNotEmpty() }; val secret = key.text.toString().trim(); val socksPort = port.text.toString().toIntOrNull() ?: 0
        Profile.validate(deployments, secret, socksPort)?.let { status.text = it; return }
        store.save(Profile(deployments, secret, socksPort)); startService(Intent(this, TunnelService::class.java)); status.text = "Starting secure SOCKS5 proxy on 127.0.0.1:$socksPort…"
    }
}
