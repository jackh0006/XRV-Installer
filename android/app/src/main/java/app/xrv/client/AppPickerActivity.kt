package app.xrv.client

import android.content.pm.PackageManager
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.CheckBox
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import app.xrv.client.databinding.ActivityAppPickerBinding
import kotlin.concurrent.thread

/** Searchable installed-app picker for TUN per-app include/exclude. */
class AppPickerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityAppPickerBinding
    private lateinit var adapter: AppAdapter
    private val selected = linkedSetOf<String>()
    private var mode = PerAppMode.INCLUDE

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityAppPickerBinding.inflate(layoutInflater)
        setContentView(binding.root)
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(binding.root)

        selected += XrvSettings.perAppPackages(this)
        mode = XrvSettings.perAppMode(this).takeIf { it != PerAppMode.ALL }
            ?: PerAppMode.INCLUDE
        binding.appPickerModeGroup.check(
            if (mode == PerAppMode.EXCLUDE) R.id.appPickerExclude else R.id.appPickerInclude
        )

        adapter = AppAdapter(LayoutInflater.from(this), selected) { updateCount() }
        binding.appList.adapter = adapter

        binding.appPickerBack.setOnClickListener { finish() }
        binding.appPickerSave.setOnClickListener { save() }
        binding.appPickerModeGroup.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked) return@addOnButtonCheckedListener
            mode = if (checkedId == R.id.appPickerExclude) {
                PerAppMode.EXCLUDE
            } else {
                PerAppMode.INCLUDE
            }
        }
        binding.selectAllButton.setOnClickListener {
            selected += adapter.visiblePackages()
            updateCount()
            adapter.notifyDataSetChanged()
        }
        binding.clearSelectionButton.setOnClickListener {
            selected.clear()
            updateCount()
            adapter.notifyDataSetChanged()
        }
        binding.appSearchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                adapter.setQuery(s?.toString().orEmpty())
            }
        })

        loadApps()
        updateCount()
    }

    private fun loadApps() {
        binding.appLoadingRow.visibility = View.VISIBLE
        binding.appList.visibility = View.INVISIBLE
        val ownPackage = packageName
        thread(name = "xrv-app-list", isDaemon = true) {
            val pm = packageManager
            val entries = ArrayList<AppEntry>()
            for (info in pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
                if (info.packageName == ownPackage) continue
                val label = runCatching {
                    pm.getApplicationLabel(info).toString()
                }.getOrNull()?.takeIf { it.isNotBlank() } ?: info.packageName
                val icon = runCatching { pm.getApplicationIcon(info) }.getOrNull()
                entries += AppEntry(info.packageName, label, icon)
            }
            entries.sortWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.label })
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                selected.retainAll(entries.map { it.packageName }.toSet())
                binding.appLoadingRow.visibility = View.GONE
                binding.appList.visibility = View.VISIBLE
                adapter.setData(entries)
                if (entries.isEmpty()) {
                    binding.appPickerCount.setText(R.string.app_picker_no_apps)
                } else {
                    updateCount()
                }
            }
        }
    }

    private fun updateCount() {
        binding.appPickerCount.text = getString(R.string.app_picker_count, selected.size)
    }

    private fun save() {
        if (mode == PerAppMode.INCLUDE && selected.isEmpty()) {
            toast(getString(R.string.app_picker_empty_selection))
            return
        }
        XrvSettings.setPerAppMode(this, mode)
        XrvSettings.setPerAppPackages(this, selected)
        XrvLog.add("per-app", "saved ${mode.name} with ${selected.size} app(s)")
        setResult(RESULT_OK)
        finish()
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    private data class AppEntry(
        val packageName: String,
        val label: String,
        val icon: Drawable?
    )

    private class AppAdapter(
        private val inflater: LayoutInflater,
        private val selected: MutableSet<String>,
        private val onChanged: () -> Unit
    ) : BaseAdapter() {
        private val all = ArrayList<AppEntry>()
        private val visible = ArrayList<AppEntry>()
        private var query: String = ""

        fun setData(items: List<AppEntry>) {
            all.clear()
            all.addAll(items)
            applyFilter()
        }

        fun setQuery(value: String) {
            query = value.trim()
            applyFilter()
        }

        fun visiblePackages(): List<String> = visible.map { it.packageName }

        private fun applyFilter() {
            visible.clear()
            if (query.isEmpty()) {
                visible.addAll(all)
            } else {
                val needle = query.lowercase()
                for (item in all) {
                    if (item.label.lowercase().contains(needle) ||
                        item.packageName.lowercase().contains(needle)
                    ) {
                        visible += item
                    }
                }
            }
            notifyDataSetChanged()
        }

        override fun getCount(): Int = visible.size
        override fun getItem(position: Int): AppEntry = visible[position]
        override fun getItemId(position: Int): Long = getItem(position).packageName.hashCode().toLong()
        override fun hasStableIds(): Boolean = false

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val view = convertView ?: inflater.inflate(R.layout.item_app, parent, false)
            val entry = getItem(position)
            val icon = view.findViewById<ImageView>(R.id.appIcon)
            val label = view.findViewById<TextView>(R.id.appLabel)
            val pkg = view.findViewById<TextView>(R.id.appPackage)
            val check = view.findViewById<CheckBox>(R.id.appCheck)

            icon.setImageDrawable(entry.icon)
            label.text = entry.label
            pkg.text = entry.packageName
            check.setOnCheckedChangeListener(null)
            check.isChecked = selected.contains(entry.packageName)
            check.setOnCheckedChangeListener { _, isChecked ->
                if (isChecked) selected += entry.packageName else selected -= entry.packageName
                onChanged()
            }
            view.setOnClickListener {
                check.isChecked = !check.isChecked
            }
            return view
        }
    }
}
