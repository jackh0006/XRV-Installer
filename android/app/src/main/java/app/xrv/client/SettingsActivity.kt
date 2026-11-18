package app.xrv.client

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import app.xrv.client.databinding.ActivitySettingsBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder

class SettingsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsBinding
    private lateinit var store: SecureProfileStore
    private var pickerOpen = false

    private val appPickerLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            pickerOpen = false
            refreshPerApp()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            view.setPadding(0, bars.top, 0, maxOf(bars.bottom, ime.bottom))
            insets
        }
        ViewCompat.requestApplyInsets(binding.root)

        store = SecureProfileStore(this)
        loadSettings()
        setupActions()
    }

    private fun loadSettings() {
        binding.settingsModeGroup.check(
            if (XrvSettings.mode(this) == Mode.PROXY) R.id.settingsBtnProxy else R.id.settingsBtnTun
        )
        val profile = store.load()
        val port = profile?.socksPort ?: XrvSettings.port(this)
        binding.settingsPortInput.setText(getString(R.string.port_value, port))
        binding.settingsCoalesceInput.setText(getString(R.string.port_value, XrvSettings.coalesceMs(this)))
        binding.settingsIdleInput.setText(
            getString(
                R.string.port_value,
                XrvSettings.idleSlots(this, profile?.deployments?.size ?: 1)
            )
        )

        binding.googleCandidatesInput.setText(
            XrvSettings.googleCandidates(this).joinToString("\n")
        )
        updateCurrentEdge()
        refreshPerApp()
    }

    private fun setupActions() {
        binding.settingsBackButton.setOnClickListener { finish() }
        binding.settingsModeGroup.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked) return@addOnButtonCheckedListener
            val mode = if (checkedId == R.id.settingsBtnProxy) Mode.PROXY else Mode.TUN
            XrvSettings.setMode(this, mode)
            XrvLog.add("settings", "default mode=${mode.name}")
            if (XrvState.read(this).active) {
                toast(getString(R.string.settings_apply_next))
            }
        }

        binding.perAppSwitch.setOnCheckedChangeListener { _, checked ->
            if (checked) {
                var mode = XrvSettings.perAppMode(this)
                if (mode == PerAppMode.ALL) {
                    mode = PerAppMode.INCLUDE
                    XrvSettings.setPerAppMode(this, mode)
                }
                binding.perAppModeGroup.check(
                    if (mode == PerAppMode.EXCLUDE) R.id.perAppExceptButton else R.id.perAppOnlyButton
                )
                if (XrvSettings.perAppPackages(this).isEmpty() &&
                    mode == PerAppMode.INCLUDE
                ) {
                    launchAppPicker()
                }
            } else {
                XrvSettings.setPerAppMode(this, PerAppMode.ALL)
                XrvLog.add("settings", "per-app disabled")
            }
            refreshPerApp()
        }

        binding.perAppModeGroup.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked || !binding.perAppSwitch.isChecked) return@addOnButtonCheckedListener
            val mode = if (checkedId == R.id.perAppExceptButton) {
                PerAppMode.EXCLUDE
            } else {
                PerAppMode.INCLUDE
            }
            XrvSettings.setPerAppMode(this, mode)
            if (mode == PerAppMode.INCLUDE && XrvSettings.perAppPackages(this).isEmpty()) {
                launchAppPicker()
            }
            refreshPerApp()
        }

        binding.chooseAppsButton.setOnClickListener { launchAppPicker() }
        binding.findEdgeButton.setOnClickListener { findEdge() }
        binding.autoEdgeButton.setOnClickListener {
            XrvSettings.setSelectedGoogleIp(this, "")
            updateCurrentEdge()
            XrvLog.add("edge", "selected automatic edge")
        }
        binding.testTunnelButton.setOnClickListener { testTunnel() }
        binding.logsButton.setOnClickListener {
            startActivity(Intent(this, LogsActivity::class.java))
        }
        binding.settingsBatteryButton.setOnClickListener { openBatterySettings() }
        binding.settingsAboutButton.setOnClickListener {
            startActivity(Intent(this, AboutActivity::class.java))
        }
        binding.settingsClearButton.setOnClickListener { confirmClear() }
        binding.saveSettingsButton.setOnClickListener { saveSettings() }
    }

    private fun refreshPerApp() {
        val mode = XrvSettings.perAppMode(this)
        val count = XrvSettings.perAppPackages(this).size
        val enabled = mode != PerAppMode.ALL
        binding.perAppSwitch.isChecked = enabled
        binding.perAppModeGroup.isEnabled = enabled
        for (i in 0 until binding.perAppModeGroup.childCount) {
            binding.perAppModeGroup.getChildAt(i).isEnabled = enabled
        }
        binding.chooseAppsButton.isEnabled = enabled
        if (enabled) {
            binding.perAppModeGroup.check(
                if (mode == PerAppMode.EXCLUDE) R.id.perAppExceptButton else R.id.perAppOnlyButton
            )
        }
        binding.perAppSummary.text = when (mode) {
            PerAppMode.ALL -> getString(R.string.per_app_summary_all)
            PerAppMode.INCLUDE -> getString(R.string.per_app_summary_include, count)
            PerAppMode.EXCLUDE -> getString(R.string.per_app_summary_exclude, count)
        }
    }

    private fun launchAppPicker() {
        if (pickerOpen) return
        pickerOpen = true
        appPickerLauncher.launch(Intent(this, AppPickerActivity::class.java))
    }

    private fun updateCurrentEdge() {
        val selected = XrvSettings.selectedGoogleIp(this)
        binding.currentEdgeText.text = if (selected.isEmpty()) {
            getString(R.string.google_current_auto, XrvSettings.defaultGoogleIp)
        } else {
            getString(R.string.google_current, selected)
        }
    }

    private fun findEdge() {
        val candidates = IpUtils.parseCandidates(
            binding.googleCandidatesInput.text?.toString().orEmpty()
        )
        if (candidates.isEmpty()) {
            binding.googleCandidatesLayout.error = getString(R.string.google_invalid)
            return
        }
        binding.googleCandidatesLayout.error = null
        XrvSettings.setGoogleCandidates(this, candidates)
        binding.googleCandidatesInput.setText(candidates.joinToString("\n"))
        binding.edgeProgress.visibility = View.VISIBLE
        binding.edgeResultsText.visibility = View.VISIBLE
        binding.edgeResultsText.setText(R.string.google_testing)
        binding.findEdgeButton.isEnabled = false
        EdgeProber.run(candidates) { report ->
            binding.edgeProgress.visibility = View.GONE
            binding.findEdgeButton.isEnabled = true
            val text = StringBuilder()
            for (result in report.results) {
                if (result.ok) {
                    text.append(getString(R.string.google_result_ok, result.ip, result.ms))
                } else {
                    text.append(getString(R.string.google_result_bad, result.ip))
                }
                text.append('\n')
            }
            if (report.best != null) {
                XrvSettings.setSelectedGoogleIp(this, report.best)
                updateCurrentEdge()
                text.append('\n')
                text.append(getString(R.string.google_selected, report.best, report.bestMs))
                XrvLog.add("edge", "best=${report.best} ms=${report.bestMs}")
            } else {
                text.append('\n')
                text.append(getString(R.string.google_no_best))
                XrvLog.add("edge", "probe failed: ${report.error ?: "no best"}")
            }
            binding.edgeResultsText.text = text.toString().trimEnd()
        }
    }

    private fun testTunnel() {
        val state = XrvState.read(this)
        if (state.phase != Phase.RUNNING) {
            toast(getString(R.string.diagnostics_connect_first))
            return
        }
        val profile = store.load() ?: run {
            toast(getString(R.string.error_no_profile))
            return
        }
        binding.testResultText.visibility = View.VISIBLE
        binding.testResultText.setText(R.string.diagnostics_testing)
        binding.testTunnelButton.isEnabled = false
        ConnectionTester.run(
            this,
            state.port,
            profile.socksUser,
            profile.socksPass
        ) { result ->
            binding.testTunnelButton.isEnabled = true
            val text = when {
                !result.ok -> getString(
                    R.string.diagnostics_result_fail,
                    result.error ?: "unknown error"
                )
                result.realIp != null && result.realIp == result.exitIp -> getString(
                    R.string.diagnostics_result_same,
                    result.exitIp, result.ms, result.realIp
                )
                result.realIp != null -> getString(
                    R.string.diagnostics_result_ok,
                    result.exitIp, result.ms, result.realIp
                )
                else -> getString(
                    R.string.diagnostics_result_no_real,
                    result.exitIp, result.ms
                )
            }
            binding.testResultText.text = text
            XrvLog.add("test", "ok=${result.ok} exit=${result.exitIp} ms=${result.ms}")
        }
    }

    private fun saveSettings() {
        val port = binding.settingsPortInput.text?.toString()?.trim()?.toIntOrNull()
        if (port == null || port !in Profile.MIN_PORT..Profile.MAX_PORT) {
            binding.settingsPortLayout.error = getString(R.string.error_port_setting)
            return
        }
        val coalesce = binding.settingsCoalesceInput.text?.toString()?.trim()?.toIntOrNull()
        if (coalesce == null || coalesce !in 0..1000) {
            binding.settingsCoalesceLayout.error = getString(R.string.error_coalesce_setting)
            return
        }
        val idle = binding.settingsIdleInput.text?.toString()?.trim()?.toIntOrNull()
        if (idle == null || idle !in 1..3) {
            binding.settingsIdleLayout.error = getString(R.string.error_idle_setting)
            return
        }
        val candidates = IpUtils.parseCandidates(
            binding.googleCandidatesInput.text?.toString().orEmpty()
        )
        if (candidates.isEmpty()) {
            binding.googleCandidatesLayout.error = getString(R.string.google_invalid)
            return
        }
        if (XrvSettings.perAppMode(this) == PerAppMode.INCLUDE &&
            XrvSettings.perAppPackages(this).isEmpty()
        ) {
            toast(getString(R.string.error_no_per_app))
            return
        }
        binding.settingsPortLayout.error = null
        binding.settingsCoalesceLayout.error = null
        binding.settingsIdleLayout.error = null
        binding.googleCandidatesLayout.error = null

        XrvSettings.setPort(this, port)
        XrvSettings.setCoalesceMs(this, coalesce)
        XrvSettings.setIdleSlots(this, idle)
        XrvSettings.setGoogleCandidates(this, candidates)
        store.load()?.let { store.save(it.copy(socksPort = port).normalized()) }
        val active = XrvState.read(this).active
        toast(
            getString(
                if (active) R.string.settings_saved_reconnect else R.string.settings_saved
            )
        )
        XrvLog.add("settings", "saved port=$port coalesce=$coalesce idle=$idle")
        finish()
    }

    private fun confirmClear() {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.clear_title)
            .setMessage(R.string.clear_message)
            .setPositiveButton(R.string.clear_confirm) { _, _ ->
                store.clear()
                XrvSettings.setPort(this, Profile.DEFAULT_PORT)
                XrvLog.add("settings", "configuration cleared")
                toast(getString(R.string.cleared))
                finish()
            }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun openBatterySettings() {
        val intents = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
        for (intent in intents) {
            if (runCatching { startActivity(intent) }.isSuccess) return
        }
        toast(getString(R.string.battery_button))
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }
}
