package com.rivlus.project_tcr

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin

/**
 * OAuth callback activity: Chrome Custom Tab'dan gelen redirect'i yakalar,
 * sonucu flutter_web_auth_2 plugin'ine iletir ve ana ekranı öne getirir.
 *
 * Paketin kendi CallbackActivity'si sadece [finishAndRemoveTask] çağırıyor
 * ama Chrome Custom Tab ayrı bir task/process'te çalıştığı için kapanmıyor.
 * Bu activity, callback'i işledikten sonra [MainActivity]'yi FLAG_ACTIVITY_CLEAR_TOP
 * ile başlatarak Custom Tab'ı arka plana iter ve uygulamayı öne getirir.
 */
class OAuthCallbackActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent?.data
        val scheme = url?.scheme

        // Callback URL'ini flutter_web_auth_2 plugin'ine ilet
        if (scheme != null) {
            FlutterWebAuth2Plugin.callbacks.remove(scheme)?.success(url.toString())
        }

        // Ana activity'yi öne getir (Chrome Custom Tab arka plana gider)
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (launchIntent != null) {
            startActivity(launchIntent)
        }

        finish()
    }
}
