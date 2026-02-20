package com.pimobile.app.repository

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class ApiKeyRepository(context: Context) {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "pi_api_keys",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun getApiKey(provider: String): String? {
        return prefs.getString("api_key_$provider", null)
    }

    fun setApiKey(provider: String, apiKey: String) {
        prefs.edit().putString("api_key_$provider", apiKey).apply()
    }

    fun removeApiKey(provider: String) {
        prefs.edit().remove("api_key_$provider").apply()
    }

    fun hasApiKey(provider: String): Boolean {
        return prefs.contains("api_key_$provider")
    }

    fun getAllProviders(): Set<String> {
        return prefs.all.keys
            .filter { it.startsWith("api_key_") }
            .map { it.removePrefix("api_key_") }
            .toSet()
    }

    // Provider settings (e.g. Azure endpoint URL)

    fun getSetting(provider: String, key: String): String? {
        return prefs.getString("setting_${provider}_$key", null)
    }

    fun setSetting(provider: String, key: String, value: String) {
        prefs.edit().putString("setting_${provider}_$key", value).apply()
    }

    fun removeSetting(provider: String, key: String) {
        prefs.edit().remove("setting_${provider}_$key").apply()
    }

    fun getDefaultModel(): String? {
        return prefs.getString("default_model", null)
    }

    fun setDefaultModel(modelKey: String) {
        prefs.edit().putString("default_model", modelKey).apply()
    }

    fun getDefaultProvider(): String? {
        return prefs.getString("default_provider", null)
    }

    fun setDefaultProvider(provider: String) {
        prefs.edit().putString("default_provider", provider).apply()
    }
}
