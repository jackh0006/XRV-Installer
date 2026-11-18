package app.xrv.client

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import app.xrv.client.databinding.ActivityAboutBinding
import com.google.android.material.button.MaterialButton

class AboutActivity : AppCompatActivity() {
    private lateinit var binding: ActivityAboutBinding

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityAboutBinding.inflate(layoutInflater)
        setContentView(binding.root)

        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            view.setPadding(0, bars.top, 0, bars.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(binding.root)

        binding.versionText.text = getString(R.string.about_version, BuildConfig.VERSION_NAME)
        binding.backButton.setOnClickListener { finish() }
        binding.sourceButton.setOnClickListener {
            runCatching {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(getString(R.string.about_source_url))))
            }
        }

        wallets.forEach { (network, address) ->
            val button = layoutInflater.inflate(R.layout.item_wallet, binding.walletContainer, false)
                as MaterialButton
            button.text = getString(R.string.wallet_entry, network, address)
            button.setOnClickListener {
                val clipboard = getSystemService(ClipboardManager::class.java)
                clipboard?.setPrimaryClip(
                    ClipData.newPlainText(getString(R.string.app_name), address)
                )
                Toast.makeText(
                    this@AboutActivity,
                    getString(R.string.wallet_copied),
                    Toast.LENGTH_SHORT
                ).show()
            }
            binding.walletContainer.addView(button)
        }

        binding.walletContainer.visibility = if (wallets.isEmpty()) View.GONE else View.VISIBLE
    }
}
