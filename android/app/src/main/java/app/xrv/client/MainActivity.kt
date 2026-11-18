package app.xrv.client

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.transition.AutoTransition
import android.transition.TransitionManager
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import app.xrv.client.databinding.ActivityMainBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import kotlin.math.roundToInt

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private lateinit var store: SecureProfileStore
    private val deploymentLayouts = mutableListOf<TextInputLayout>()
    private val deploymentInputs = mutableListOf<TextInputEditText>()
    private val handler = Handler(Looper.getMainLooper())
    private var advancedOpen = false
    private var pulseAnimator: ObjectAnimator? = null
    private var receiverRegistered = false

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = render()
    }

    private val poller = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, 1_000)
        }
    }

    private val vpnPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == RESULT_OK) {
                startVpn()
            } else {
                XrvState.stopped(this)
                toast(getString(R.string.error_vpn_denied))
            }
        }

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* optional */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applyInsets()

        store = SecureProfileStore(this)
        buildDeploymentFields()
        restoreProfile()
        restoreMode()
        setupActions()
        render()

        if (store.load() == null) {
            setAdvanced(true, animate = false)
            deploymentInputs.firstOrNull()?.requestFocus()
        }
        verifyStateFreshness()
    }

    /**
     * If the process was killed without stopping the service cleanly, the
     * persisted state can claim RUNNING while no service owns the engine.
     */
    private fun verifyStateFreshness() {
        handler.postDelayed({
            val state = XrvState.read(this)
            if (state.phase == Phase.RUNNING &&
                !TunnelService.isRunning &&
                !XrvVpnService.isRunning
            ) {
                XrvState.stopped(this)
            }
        }, 3_000)
    }

    private fun applyInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            view.setPadding(0, bars.top, 0, bars.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(binding.root)
    }

    private fun buildDeploymentFields() {
        binding.deploymentContainer.removeAllViews()
        deploymentLayouts.clear()
        deploymentInputs.clear()
        repeat(Profile.MAX_DEPLOYMENTS) { index ->
            val layout = TextInputLayout(this).apply {
                hint = if (index == 0) {
                    getString(R.string.deployment_1)
                } else {
                    getString(R.string.deployment_n, index + 1)
                }
                boxBackgroundMode = TextInputLayout.BOX_BACKGROUND_OUTLINE
                setBoxCornerRadii(
                    dp(14f).toFloat(), dp(14f).toFloat(),
                    dp(14f).toFloat(), dp(14f).toFloat()
                )
                setHelperTextEnabled(false)
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = if (index == 0) 0 else dp(12f) }
            }
            val input = TextInputEditText(layout.context).apply {
                inputType = InputType.TYPE_CLASS_TEXT
                setSingleLine(true)
                textSize = 14f
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
                }
                setOnFocusChangeListener { _, focused -> if (focused) layout.error = null }
            }
            layout.addView(
                input,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
            binding.deploymentContainer.addView(layout)
            deploymentLayouts += layout
            deploymentInputs += input
        }
        binding.keyInput.setOnFocusChangeListener { _, focused ->
            if (focused) binding.keyLayout.error = null
        }
        binding.portInput.setOnFocusChangeListener { _, focused ->
            if (focused) binding.portLayout.error = null
        }
    }

    private fun restoreProfile() {
        val profile = store.load() ?: return
        profile.deployments.forEachIndexed { index, value ->
            deploymentInputs.getOrNull(index)?.setText(value)
        }
        binding.keyInput.setText(profile.tunnelKey)
        binding.portInput.setText(getString(R.string.port_value, profile.socksPort))
        updateAdvancedSummary()
    }

    private fun restoreMode() {
        val mode = XrvSettings.mode(this)
        binding.modeGroup.check(if (mode == Mode.PROXY) R.id.btnProxy else R.id.btnTun)
    }

    private fun setupActions() {
        binding.aboutButton.setOnClickListener {
            startActivity(Intent(this, AboutActivity::class.java))
        }
        binding.advancedHeader.setOnClickListener {
            setAdvanced(!advancedOpen)
        }
        binding.connectButton.setOnClickListener { onConnectClicked() }
        binding.detailsButton.setOnClickListener { showDetails() }
        binding.copyProxyButton.setOnClickListener { copyProxyAddress() }
        binding.copyProxyButton2.setOnClickListener { copyProxyAddress() }
        binding.batteryButton.setOnClickListener { openBatterySettings() }
        binding.clearButton.setOnClickListener { confirmClear() }

        binding.modeGroup.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked) return@addOnButtonCheckedListener
            val mode = if (checkedId == R.id.btnProxy) Mode.PROXY else Mode.TUN
            XrvSettings.setMode(this, mode)
            updateModeHint()
            render()
        }
    }

    private fun selectedMode(): Mode =
        if (binding.modeGroup.checkedButtonId == R.id.btnProxy) Mode.PROXY else Mode.TUN

    private fun onConnectClicked() {
        val snapshot = XrvState.read(this)
        if (snapshot.active) {
            disconnect()
            return
        }
        val profile = collectProfile() ?: return
        store.save(profile)
        updateAdvancedSummary()
        requestNotificationPermission()
        when (selectedMode()) {
            Mode.PROXY -> startProxy()
            Mode.TUN -> startTunWithChecks()
        }
    }

    private fun collectProfile(): Profile? {
        clearErrors()
        val ids = deploymentInputs.map {
            Profile.normalizeDeployment(it.text?.toString().orEmpty())
        }
        val key = Profile.normalizeKey(binding.keyInput.text?.toString().orEmpty())
        val port = binding.portInput.text?.toString()?.trim()?.toIntOrNull() ?: 0
        val nonEmpty = ids.filter { it.isNotEmpty() }

        ids.forEachIndexed { index, value ->
            if (value.isNotEmpty() && !Profile.isDeploymentId(value)) {
                deploymentLayouts[index].error = getString(R.string.error_deployment_field)
            }
        }
        val duplicates = nonEmpty.groupingBy { it }.eachCount().filterValues { it > 1 }.keys
        if (duplicates.isNotEmpty()) {
            ids.forEachIndexed { index, value ->
                if (value in duplicates) {
                    deploymentLayouts[index].error = getString(R.string.error_duplicate_field)
                }
            }
        }
        if (key.isNotEmpty() && !Regex("^[0-9a-fA-F]{64}$").matches(key)) {
            binding.keyLayout.error = getString(R.string.error_key_field)
        }
        if (port != 0 && port !in Profile.MIN_PORT..Profile.MAX_PORT) {
            binding.portLayout.error = getString(R.string.error_port_field)
        }

        val error = Profile.validate(ids, key, port)
        if (error != null) {
            if (nonEmpty.isEmpty()) {
                deploymentLayouts.first().error = error
            } else if (key.isEmpty()) {
                binding.keyLayout.error = error
            } else if (port == 0) {
                binding.portLayout.error = error
            }
            toast(error)
            setAdvanced(true)
            return null
        }
        return Profile(nonEmpty, key, port).normalized()
    }

    private fun clearErrors() {
        deploymentLayouts.forEach { it.error = null }
        binding.keyLayout.error = null
        binding.portLayout.error = null
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun startProxy() {
        // Stop the VPN service first and wait until it has released the
        // process-wide engine before starting a second listener.
        XrvVpnService.stop(this)
        runCatching { stopService(Intent(this, XrvVpnService::class.java)) }
        awaitStopped({ !XrvVpnService.isRunning }, {
            runCatching { TunnelService.start(this) }.onFailure { reportStartFailure(it) }
        })
    }

    private fun startTunWithChecks() {
        if (anotherVpnActive()) {
            MaterialAlertDialogBuilder(this)
                .setTitle(R.string.vpn_conflict_title)
                .setMessage(R.string.vpn_conflict_message)
                .setPositiveButton(R.string.vpn_conflict_continue) { _, _ -> requestVpnPermission() }
                .setNeutralButton(R.string.vpn_permission_use_proxy) { _, _ ->
                    binding.modeGroup.check(R.id.btnProxy)
                    XrvSettings.setMode(this, Mode.PROXY)
                    startProxy()
                }
                .setNegativeButton(R.string.cancel, null)
                .show()
            return
        }
        requestVpnPermission()
    }

    private fun requestVpnPermission() {
        if (!XrvSettings.vpnExplained(this)) {
            MaterialAlertDialogBuilder(this)
                .setTitle(R.string.vpn_permission_title)
                .setMessage(R.string.vpn_permission_message)
                .setPositiveButton(R.string.vpn_permission_continue) { _, _ ->
                    XrvSettings.setVpnExplained(this)
                    launchVpnPrepare()
                }
                .setNeutralButton(R.string.vpn_permission_use_proxy) { _, _ ->
                    binding.modeGroup.check(R.id.btnProxy)
                    XrvSettings.setMode(this, Mode.PROXY)
                    startProxy()
                }
                .setNegativeButton(R.string.cancel, null)
                .show()
            return
        }
        launchVpnPrepare()
    }

    private fun launchVpnPrepare() {
        val prepare = runCatching { VpnService.prepare(this) }.getOrNull()
        if (prepare == null) {
            startVpn()
        } else {
            vpnPermissionLauncher.launch(prepare)
        }
    }

    private fun startVpn() {
        stopService(Intent(this, TunnelService::class.java))
        awaitStopped({ !TunnelService.isRunning }, {
            runCatching { XrvVpnService.start(this) }.onFailure { reportStartFailure(it) }
        })
    }

    private fun awaitStopped(stopped: () -> Boolean, action: () -> Unit, waited: Long = 0) {
        if (stopped()) {
            action()
            return
        }
        if (waited >= 4_000) {
            reportStartFailure(IllegalStateException(getString(R.string.error_start_failed)))
            return
        }
        handler.postDelayed({ awaitStopped(stopped, action, waited + 100) }, 100)
    }

    private fun reportStartFailure(t: Throwable) {
        val message = t.message ?: getString(R.string.error_start_failed)
        XrvState.failed(this, selectedMode(), message)
        toast(message)
    }

    private fun disconnect() {
        TunnelService.stop(this)
        XrvVpnService.stop(this)
        // Also cover a dead service that cannot receive the stop action.
        runCatching { stopService(Intent(this, TunnelService::class.java)) }
        runCatching { stopService(Intent(this, XrvVpnService::class.java)) }
        if (!TunnelService.isRunning && !XrvVpnService.isRunning) {
            Engine.stop()
        }
        XrvState.stopped(this)
    }

    private fun render() {
        val snapshot = XrvState.read(this)
        val mode = snapshot.mode ?: selectedMode()
        val phase = snapshot.phase
        val running = phase == Phase.RUNNING
        val starting = phase == Phase.STARTING
        val failed = phase == Phase.ERROR

        binding.busy.visibility = if (starting) View.VISIBLE else View.GONE
        binding.statusDot.setBackgroundResource(
            when {
                running -> R.drawable.dot_ok
                starting -> R.drawable.dot_warn
                failed -> R.drawable.dot_error
                else -> R.drawable.dot_idle
            }
        )

        when {
            running && mode == Mode.TUN -> {
                binding.statusTitle.setText(R.string.status_tun_title)
                binding.statusSub.setText(R.string.status_tun_sub)
            }
            running -> {
                binding.statusTitle.setText(R.string.status_proxy_title)
                binding.statusSub.text = getString(R.string.status_proxy_sub, snapshot.port)
            }
            starting -> {
                binding.statusTitle.setText(R.string.status_starting_title)
                binding.statusSub.setText(R.string.status_starting_sub)
            }
            failed -> {
                binding.statusTitle.setText(R.string.status_error_title)
                binding.statusSub.text = snapshot.message ?: getString(R.string.status_error_sub)
            }
            else -> {
                binding.statusTitle.setText(R.string.status_disconnected_title)
                binding.statusSub.setText(R.string.status_disconnected_sub)
            }
        }

        val showStats = running && mode == Mode.TUN
        binding.statsRow.visibility = if (showStats) View.VISIBLE else View.GONE
        if (showStats) {
            binding.txText.text = Format.bytes(snapshot.txBytes)
            binding.rxText.text = Format.bytes(snapshot.rxBytes)
            binding.timeText.text = Format.duration(
                if (snapshot.startedAt > 0) System.currentTimeMillis() - snapshot.startedAt else 0
            )
        }

        val showProxy = running && mode == Mode.PROXY
        binding.proxyRow.visibility = if (showProxy) View.VISIBLE else View.GONE
        binding.shareCard.visibility = if (showProxy) View.VISIBLE else View.GONE
        if (showProxy) {
            val address = getString(R.string.proxy_address, snapshot.port)
            binding.proxyText.text = address
        } else if (running && mode == Mode.TUN) {
            binding.proxyText.text = getString(R.string.proxy_address, snapshot.port)
        }

        binding.detailsButton.visibility = if (failed) View.VISIBLE else View.GONE
        binding.connectButton.isEnabled = !starting
        binding.connectButton.text = when {
            starting -> getString(R.string.connect_starting)
            running -> getString(R.string.disconnect)
            else -> getString(R.string.connect)
        }
        val bg = if (running) R.color.xrv_error_container else R.color.xrv_primary
        val fg = if (running) R.color.xrv_on_error_container else R.color.xrv_on_primary
        binding.connectButton.backgroundTintList =
            ColorStateList.valueOf(ContextCompat.getColor(this, bg))
        binding.connectButton.setTextColor(ContextCompat.getColor(this, fg))
        binding.connectButton.iconTint =
            ColorStateList.valueOf(ContextCompat.getColor(this, fg))

        val locked = snapshot.active
        binding.modeGroup.isEnabled = !locked
        for (i in 0 until binding.modeGroup.childCount) {
            binding.modeGroup.getChildAt(i).isEnabled = !locked
        }
        binding.advancedHeader.isEnabled = true

        setPulse(running)
        updateModeHint(snapshot)
    }

    private fun setPulse(on: Boolean) {
        if (on && pulseAnimator == null) {
            pulseAnimator = ObjectAnimator.ofFloat(binding.statusDot, View.ALPHA, 1f, 0.35f).apply {
                duration = 900
                repeatMode = ValueAnimator.REVERSE
                repeatCount = ValueAnimator.INFINITE
                start()
            }
        } else if (!on && pulseAnimator != null) {
            pulseAnimator?.cancel()
            pulseAnimator = null
            binding.statusDot.alpha = 1f
        }
    }

    private fun updateModeHint(snapshot: XrvSnapshot = XrvState.read(this)) {
        val mode = selectedMode()
        val conflict = !snapshot.active && anotherVpnActive()
        binding.modeHint.setText(
            when {
                conflict && mode == Mode.TUN -> R.string.mode_conflict_hint
                mode == Mode.TUN -> R.string.mode_tun_hint
                else -> R.string.mode_proxy_hint
            }
        )
        binding.modeHint.setTextColor(
            ContextCompat.getColor(
                this,
                if (conflict && mode == Mode.TUN) R.color.xrv_status_warn
                else R.color.xrv_on_surface_variant
            )
        )
    }

    @Suppress("DEPRECATION")
    private fun anotherVpnActive(): Boolean {
        if (XrvVpnService.isRunning) return false
        return try {
            val cm = getSystemService(ConnectivityManager::class.java) ?: return false
            cm.allNetworks.any { network ->
                cm.getNetworkCapabilities(network)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun setAdvanced(open: Boolean, animate: Boolean = true) {
        if (advancedOpen == open) return
        advancedOpen = open
        if (animate) {
            TransitionManager.beginDelayedTransition(
                binding.root,
                AutoTransition().setDuration(200)
            )
        }
        binding.advancedBody.visibility = if (open) View.VISIBLE else View.GONE
        binding.advancedChevron.animate()
            .rotation(if (open) 180f else 0f)
            .setDuration(180)
            .start()
    }

    private fun updateAdvancedSummary() {
        val profile = store.load()
        val count = profile?.deployments?.size ?: 0
        binding.advancedSummary.text = if (count == 0) {
            getString(R.string.advanced_summary)
        } else {
            resources.getQuantityString(R.plurals.advanced_configured, count, count)
        }
    }

    private fun copyProxyAddress() {
        val snapshot = XrvState.read(this)
        val port = if (snapshot.port > 0) snapshot.port else (store.load()?.socksPort ?: Profile.DEFAULT_PORT)
        val address = getString(R.string.proxy_address, port)
        val clipboard = getSystemService(ClipboardManager::class.java) ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText(getString(R.string.app_name), address))
        toast(getString(R.string.address_copied))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            handler.postDelayed({
                runCatching {
                    if (clipboard.primaryClip?.getItemAt(0)?.text?.toString() == address) {
                        clipboard.clearPrimaryClip()
                    }
                }
            }, 60_000)
        }
    }

    private fun showDetails() {
        val snapshot = XrvState.read(this)
        val profile = store.load()
        val details = buildString {
            appendLine("Version: ${BuildConfig.VERSION_NAME}")
            appendLine("Mode: ${snapshot.mode ?: selectedMode()}")
            appendLine("State: ${snapshot.phase}")
            if (snapshot.port > 0) appendLine("Port: 127.0.0.1:${snapshot.port}")
            appendLine("Configuration: ${if (profile != null) "saved" else "missing"}")
            appendLine("Native library: ${NativeBridge.loadError ?: "loaded"}")
            appendLine("TUN engine: ${if (XrvVpnService.isRunning) "running" else "stopped"}")
            snapshot.message?.let { appendLine(); appendLine(it) }
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.error_details_title)
            .setMessage(details)
            .setPositiveButton(R.string.close, null)
            .show()
    }

    private fun confirmClear() {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.clear_title)
            .setMessage(R.string.clear_message)
            .setPositiveButton(R.string.clear_confirm) { _, _ ->
                store.clear()
                deploymentInputs.forEach { it.setText("") }
                binding.keyInput.setText("")
                binding.portInput.setText(getString(R.string.port_value, Profile.DEFAULT_PORT))
                clearErrors()
                updateAdvancedSummary()
                toast(getString(R.string.cleared))
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

    override fun onStart() {
        super.onStart()
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                this,
                stateReceiver,
                IntentFilter(XrvState.ACTION_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            receiverRegistered = true
        }
        handler.removeCallbacks(poller)
        handler.post(poller)
    }

    override fun onStop() {
        handler.removeCallbacks(poller)
        if (receiverRegistered) {
            runCatching { unregisterReceiver(stateReceiver) }
            receiverRegistered = false
        }
        super.onStop()
    }

    override fun onDestroy() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        super.onDestroy()
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    private fun dp(value: Float): Int = (value * resources.displayMetrics.density).roundToInt()
}
