package com.poemath.app

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/** 独立的文件合成引擎，不接管 flutter_tts 的朗读回调。支持 API 24。 */
class TextbookTtsFileSynthesizer(private val context: Context) : MethodChannel.MethodCallHandler {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: TextToSpeech? = null
    private var ready = false
    private var initGeneration = 0
    private var initTimeout: Runnable? = null
    private data class Waiting(val session: Int?, val result: MethodChannel.Result, val run: () -> Unit)
    private val waiting = mutableListOf<Waiting>()
    private data class Job(val id: String, val session: Int, val text: String,
        val voice: Map<*, *>?, val speed: Double, val result: MethodChannel.Result,
        var file: File? = null, var timeout: Runnable? = null)
    private val jobs = linkedMapOf<String, Job>()
    private var active: Job? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "describeVoice" -> withEngine(null, result) {
                try { result.success(identity(call.argument("voice"), call.argument<Double>("speed") ?: 0.5)) }
                catch (_: Exception) { result.error("VOICE_UNAVAILABLE", "系统中文音色不可用", null) }
            }
            "synthesize" -> {
                val session = call.argument<Int>("sessionId")
                val request = call.argument<Int>("requestId")
                val text = call.argument<String>("text")
                if (session == null || request == null || text.isNullOrBlank() ||
                    text.length > TextToSpeech.getMaxSpeechInputLength()) {
                    result.error("INVALID_TEXT", "正文为空或超过语音引擎长度限制", null)
                    return
                }
                withEngine(session, result) {
                    val id = "$session-$request"
                    jobs[id] = Job(id, session, text, call.argument("voice"),
                        call.argument<Double>("speed") ?: 0.5, result)
                    startNext()
                }
            }
            "cancelSession" -> {
                call.argument<Int>("sessionId")?.let { cancelSession(it) }
                result.success(null)
            }
            "dispose" -> { dispose(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun withEngine(session: Int?, result: MethodChannel.Result, run: () -> Unit) {
        if (ready) { run(); return }
        waiting.add(Waiting(session, result, run))
        if (engine != null) return
        val generation = ++initGeneration
        val timeout = Runnable {
            if (generation == initGeneration && !ready) failInitialization()
        }
        initTimeout = timeout
        handler.postDelayed(timeout, 15000)
        engine = TextToSpeech(context.applicationContext) { status ->
            handler.post {
                if (generation != initGeneration) return@post
                if (status != TextToSpeech.SUCCESS) { failInitialization(); return@post }
                ready = true
                initTimeout?.let { handler.removeCallbacks(it) }
                initTimeout = null
                engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(id: String) { /* 文件写入开始，不是播放开始。 */ }
                    override fun onDone(id: String) { handler.post { finish(id, true) } }
                    @Deprecated("Legacy engine callback")
                    override fun onError(id: String) { handler.post { finish(id, false) } }
                    override fun onError(id: String, errorCode: Int) { handler.post { finish(id, false) } }
                    override fun onStop(id: String, interrupted: Boolean) { handler.post { finish(id, false) } }
                })
                val pending = waiting.toList()
                waiting.clear()
                pending.forEach { it.run() }
            }
        }
    }

    private fun failInitialization() {
        ++initGeneration
        initTimeout?.let { handler.removeCallbacks(it) }
        initTimeout = null
        waiting.forEach { it.result.error("INIT_FAILED", "系统语音引擎初始化失败", null) }
        waiting.clear()
        engine?.shutdown()
        engine = null
        ready = false
    }

    private fun identity(voice: Map<*, *>?, speed: Double): String {
        val tts = engine ?: throw IllegalStateException()
        val language = tts.setLanguage(Locale.forLanguageTag(voice?.get("locale")?.toString() ?: "zh-CN"))
        if (language < 0) throw IllegalStateException("missing language")
        val name = voice?.get("name")?.toString()
        if (name != null) {
            val selected = tts.voices?.firstOrNull { it.name == name } ?: throw IllegalStateException("missing voice")
            if (tts.setVoice(selected) == TextToSpeech.ERROR) throw IllegalStateException("invalid voice")
        }
        if (tts.setSpeechRate((speed.coerceIn(0.1, 1.0) * 2).toFloat()) == TextToSpeech.ERROR) {
            throw IllegalStateException("invalid rate")
        }
        tts.setPitch(1.0f)
        val actual = tts.voice ?: throw IllegalStateException("no voice")
        val packageName = tts.defaultEngine ?: "default"
        val info = context.packageManager.getPackageInfo(packageName, 0)
        val version = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return "$packageName|$version|${actual.name}|${actual.locale.toLanguageTag()}|${speed * 2}|wav"
    }

    private fun startNext() {
        if (active != null || !ready) return
        val job = jobs.values.firstOrNull() ?: return
        active = job
        try {
            identity(job.voice, job.speed)
            val directory = File(context.cacheDir, "textbook-tts-pending")
            directory.mkdirs()
            val file = File.createTempFile("tts-${job.session}-", ".wav", directory)
            job.file = file
            val timeout = Runnable {
                if (active?.id == job.id) {
                    engine?.stop()
                    finish(job.id, false)
                }
            }
            job.timeout = timeout
            handler.postDelayed(timeout, 30000)
            val status = engine!!.synthesizeToFile(job.text, Bundle(), file, job.id)
            if (status == TextToSpeech.ERROR) finish(job.id, false)
        } catch (_: Exception) { finish(job.id, false) }
    }

    private fun finish(id: String, success: Boolean) {
        val job = jobs.remove(id) ?: return // 取消或重复回调均无副作用。
        job.timeout?.let { handler.removeCallbacks(it) }
        if (active?.id == id) active = null
        val file = job.file
        if (success && file != null && file.exists() && file.length() > 0) {
            job.result.success(file.absolutePath)
        } else {
            file?.delete()
            job.result.error("SYNTHESIS_FAILED", "系统音频生成失败，请稍后重试", null)
        }
        startNext()
    }

    private fun cancelSession(session: Int) {
        val pending = waiting.filter { it.session == session }
        waiting.removeAll(pending.toSet())
        pending.forEach { it.result.error("CANCELLED", "已停止朗读", null) }
        val selected = jobs.values.filter { it.session == session }
        // 旧会话的迟到取消不能停止新会话的引擎。
        if (active?.session == session) { active = null; engine?.stop() }
        selected.forEach {
            jobs.remove(it.id)
            it.timeout?.let { timer -> handler.removeCallbacks(timer) }
            it.file?.delete()
            it.result.error("CANCELLED", "已停止朗读", null)
        }
        startNext()
    }

    fun dispose() {
        ready = false
        ++initGeneration
        initTimeout?.let { handler.removeCallbacks(it) }
        initTimeout = null
        waiting.forEach { it.result.error("CANCELLED", "已停止朗读", null) }
        waiting.clear()
        jobs.values.map { it.session }.distinct().forEach { cancelSession(it) }
        engine?.stop()
        engine?.shutdown()
        engine = null
        ready = false
    }
}
