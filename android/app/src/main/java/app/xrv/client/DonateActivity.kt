package app.xrv.client

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.content.res.Configuration
import android.view.Gravity
import android.widget.*
import androidx.appcompat.app.AppCompatActivity

class DonateActivity : AppCompatActivity() {
    private val wallets = listOf(
        "Bitcoin (BTC)" to "bc1q8t0fn2yrsy4lh3m0pz34uj27t8vxjeavkjym83",
        "Dogecoin (DOGE)" to "D6ZdMQ7mHGGmuH9prpZ2zjpnG5Q3WVRDtC",
        "Ethereum / USDT ERC-20 / BNB / USDT BEP-20" to "0xdad428900a4359be8f76b3062df34211582e09eb",
        "TRON / USDT TRC-20" to "TMpb6RNTuGNM1eTakm9kjds1mRTPYYJesf",
        "Solana / USDT SPL / USDC SPL" to "BDCCrRez1yD1RpkAtiqKKDk3BfxPD8P7nkL26jCYrzgL",
        "XRP" to "rNUAhaATFLvosdu9m9M95bupRBtZ8eqpj9",
        "TON" to "UQCu6-3yGyQ5dzvcCxr2gobuvx5ddbS9EC690qtey92P5_wX",
        "Litecoin (LTC)" to "ltc1q2gs89cfy3mumr7gu9w0zl9rllf80q67m5rmma8"
    )
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState)
        val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val bg = if (dark) Color.rgb(9,17,31) else Color.rgb(247,249,252); val textColor = if (dark) Color.rgb(234,242,255) else Color.rgb(20,30,45)
        val scroll = ScrollView(this); val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(42,48,42,42); setBackgroundColor(bg) }
        fun text(value: String, size: Float = 14f) = TextView(this).apply { this.text=value; textSize=size; setTextColor(textColor); setPadding(0,10,0,10) }
        box.addView(text("About XRV", 28f)); box.addView(text("Made by jackh0006\njackh109867@gmail.com\n\nXRV is free and open source. Donations are optional and irreversible. Verify every receiving address from the project source before sending.", 15f))
        wallets.forEach { (network, address) -> box.addView(Button(this).apply { text = "$network\n$address"; isAllCaps=false; gravity=Gravity.START; setOnClickListener { (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText(network, address)); Toast.makeText(this@DonateActivity, "$network address copied", Toast.LENGTH_SHORT).show() } }) }
        box.addView(text("XRV never asks for a seed phrase or private key. Only send assets on the stated network.", 12f)); scroll.addView(box); setContentView(scroll)
    }
}
