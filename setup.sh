#!/bin/bash
set -e
mkdir -p DeskPet/app/src/main/res/drawable-nodpi DeskPet/app/src/main/res/values DeskPet/app/src/main/java/com/example/deskpet
cat > DeskPet/settings.gradle <<'@@END@@'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "DeskPet"
include ':app'
@@END@@
cat > DeskPet/build.gradle <<'@@END@@'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
@@END@@
cat > DeskPet/gradle.properties <<'@@END@@'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=false
android.nonTransitiveRClass=true
@@END@@
cat > DeskPet/app/build.gradle <<'@@END@@'
plugins {
    id 'com.android.application'
}

android {
    namespace 'com.example.deskpet'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.deskpet"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    buildTypes {
        release {
            minifyEnabled false
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
@@END@@
cat > DeskPet/app/src/main/AndroidManifest.xml <<'@@END@@'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="true"
        android:icon="@drawable/ic_launcher"
        android:label="@string/app_name"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".PetService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="desktop_pet_overlay" />
        </service>
    </application>
</manifest>
@@END@@
cat > DeskPet/app/src/main/res/values/strings.xml <<'@@END@@'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">鲸鲸桌宠</string>
</resources>
@@END@@
cat > DeskPet/app/src/main/java/com/example/deskpet/PetService.java <<'@@END@@'
package com.example.deskpet;

import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.widget.ImageView;
import android.widget.TextView;

import java.util.Calendar;
import java.util.Random;

/** 悬浮桌宠服务：在所有应用上层显示角色，可拖动、点击说话、待机浮动。 */
public class PetService extends Service {

    public static final String ACTION_STOP = "com.example.deskpet.STOP";
    public static final String ACTION_RESIZE = "com.example.deskpet.RESIZE";
    public static final String PREFS = "deskpet";
    public static final String KEY_SIZE = "size_percent";
    public static final int DEFAULT_SIZE = 100;

    private static final int NOTI_ID = 1;
    private static final String CHANNEL_ID = "deskpet_channel";
    private static final int BASE_HEIGHT_DP = 200;

    private WindowManager wm;
    private WindowManager.LayoutParams petParams;
    private WindowManager.LayoutParams bubbleParams;
    private ImageView petView;
    private TextView bubbleView;
    private boolean bubbleShown = false;
    private ObjectAnimator floatAnim;
    private Bitmap petBitmap;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Random random = new Random();
    private final Runnable hideBubble = this::removeBubble;
    private final Runnable idleTalk = new Runnable() {
        @Override public void run() {
            say(pickIdleLine());
            handler.postDelayed(this, 25000 + random.nextInt(35000));
        }
    };

    private static final String[] TAP_LINES = {
            "主人，欢迎回来~",
            "诶嘿，被戳到啦~",
            "今天也要元气满满哦！",
            "鲸鲸在这里陪着你~",
            "要不要喝杯水休息一下？",
            "有什么吩咐吗，主人？",
            "咕噜咕噜……是泡泡的声音~",
            "不要一直盯着屏幕啦，眨眨眼睛~",
    };
    private static final String[] IDLE_LINES = {
            "在海里游啊游~",
            "主人加油，我在看着你哦！",
            "记得多喝水~",
            "该站起来活动一下啦！",
            "尾巴有点痒……",
    };
    private static final String[] LONG_PRESS_LINES = {
            "呀！别拎着我啦~",
            "要带我去哪里呀？",
            "抓稳了哦主人！",
    };

    @Override public IBinder onBind(Intent intent) { return null; }

    @Override public void onCreate() {
        super.onCreate();
        wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        createChannel();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        startAsForeground();
        if (petView == null) {
            showPet();
            handler.postDelayed(() -> say("主人，我来啦！"), 600);
            handler.postDelayed(idleTalk, 30000);
        } else if (ACTION_RESIZE.equals(action)) {
            applySize();
        }
        return START_STICKY;
    }

    @Override public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (floatAnim != null) floatAnim.cancel();
        removeBubble();
        if (petView != null) {
            try { wm.removeView(petView); } catch (Exception ignored) { }
            petView = null;
        }
        super.onDestroy();
    }

    // ---------------------------------------------------------------- 前台通知

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID, "桌宠运行中", NotificationManager.IMPORTANCE_MIN);
            ch.setShowBadge(false);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(ch);
        }
    }

    private void startAsForeground() {
        Intent stop = new Intent(this, PetService.class).setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(this, 0, stop,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent openPi = PendingIntent.getActivity(this, 1,
                new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);

        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        b.setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("桌宠正在陪着你")
                .setContentText("点击打开设置，或点“收起桌宠”退出")
                .setContentIntent(openPi)
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(null, "收起桌宠", stopPi).build());
        Notification n = b.build();

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTI_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTI_ID, n);
        }
    }

    // ---------------------------------------------------------------- 桌宠窗口

    private int dp(float v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private int overlayType() {
        return Build.VERSION.SDK_INT >= 26
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
    }

    private void showPet() {
        petBitmap = BitmapFactory.decodeResource(getResources(), R.drawable.pet);
        petView = new ImageView(this);
        petView.setImageBitmap(petBitmap);
        petView.setScaleType(ImageView.ScaleType.FIT_XY);

        petParams = new WindowManager.LayoutParams(
                0, 0, overlayType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT);
        petParams.gravity = Gravity.TOP | Gravity.START;

        DisplayMetrics dm = getResources().getDisplayMetrics();
        applySizeToParams();
        petParams.x = dm.widthPixels - petParams.width - dp(8);
        petParams.y = dm.heightPixels - petParams.height - dp(120);

        petView.setOnTouchListener(new DragListener());
        wm.addView(petView, petParams);

        floatAnim = ObjectAnimator.ofFloat(petView, View.TRANSLATION_Y, 0f, -dp(6));
        floatAnim.setDuration(1800);
        floatAnim.setRepeatCount(ValueAnimator.INFINITE);
        floatAnim.setRepeatMode(ValueAnimator.REVERSE);
        floatAnim.setInterpolator(new AccelerateDecelerateInterpolator());
        floatAnim.start();
    }

    private void applySizeToParams() {
        SharedPreferences sp = getSharedPreferences(PREFS, MODE_PRIVATE);
        int percent = sp.getInt(KEY_SIZE, DEFAULT_SIZE);
        int h = dp(BASE_HEIGHT_DP * percent / 100f);
        int w = Math.round(h * (petBitmap.getWidth() / (float) petBitmap.getHeight()));
        petParams.width = w;
        petParams.height = h;
    }

    private void applySize() {
        if (petView == null) return;
        applySizeToParams();
        clampToScreen();
        wm.updateViewLayout(petView, petParams);
        if (bubbleShown) positionBubble();
    }

    private void clampToScreen() {
        DisplayMetrics dm = getResources().getDisplayMetrics();
        petParams.x = Math.max(0, Math.min(petParams.x, dm.widthPixels - petParams.width));
        petParams.y = Math.max(0, Math.min(petParams.y, dm.heightPixels - petParams.height));
    }

    // ---------------------------------------------------------------- 对话气泡

    private String pickIdleLine() {
        int hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        if (hour >= 0 && hour < 5) return "这么晚了还不睡吗？要注意身体哦~";
        if (hour >= 5 && hour < 9) return "早上好，主人！今天也请多关照~";
        if (hour >= 12 && hour < 14) return "午饭时间到啦，有好好吃饭吗？";
        if (hour >= 22) return "夜深了，早点休息吧，晚安~";
        return IDLE_LINES[random.nextInt(IDLE_LINES.length)];
    }

    private void say(String text) {
        if (petView == null) return;
        handler.removeCallbacks(hideBubble);
        if (bubbleView == null) {
            bubbleView = new TextView(this);
            bubbleView.setTextColor(Color.parseColor("#2B3A55"));
            bubbleView.setTextSize(14);
            bubbleView.setMaxWidth(dp(200));
            bubbleView.setPadding(dp(12), dp(8), dp(12), dp(8));
            GradientDrawable bg = new GradientDrawable();
            bg.setColor(Color.parseColor("#F4F9FF"));
            bg.setStroke(dp(2), Color.parseColor("#7FA6D8"));
            bg.setCornerRadius(dp(14));
            bubbleView.setBackground(bg);
        }
        bubbleView.setText(text);

        if (bubbleParams == null) {
            bubbleParams = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    overlayType(),
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT);
            bubbleParams.gravity = Gravity.TOP | Gravity.START;
        }
        positionBubble();
        if (!bubbleShown) {
            wm.addView(bubbleView, bubbleParams);
            bubbleShown = true;
        } else {
            wm.updateViewLayout(bubbleView, bubbleParams);
        }
        handler.postDelayed(hideBubble, 3500);
    }

    private void positionBubble() {
        DisplayMetrics dm = getResources().getDisplayMetrics();
        bubbleView.measure(
                View.MeasureSpec.makeMeasureSpec(dm.widthPixels, View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(dm.heightPixels, View.MeasureSpec.AT_MOST));
        int bw = bubbleView.getMeasuredWidth();
        int bh = bubbleView.getMeasuredHeight();
        int x = petParams.x + petParams.width / 2 - bw / 2;
        int y = petParams.y - bh - dp(2);
        bubbleParams.x = Math.max(0, Math.min(x, dm.widthPixels - bw));
        bubbleParams.y = Math.max(0, y);
        if (bubbleShown) wm.updateViewLayout(bubbleView, bubbleParams);
    }

    private void removeBubble() {
        if (bubbleShown && bubbleView != null) {
            try { wm.removeView(bubbleView); } catch (Exception ignored) { }
        }
        bubbleShown = false;
    }

    // ---------------------------------------------------------------- 手势

    private void bounce() {
        petView.animate().cancel();
        petView.setPivotX(petView.getWidth() / 2f);
        petView.setPivotY(petView.getHeight());
        petView.setScaleX(1.08f);
        petView.setScaleY(0.92f);
        petView.animate().scaleX(1f).scaleY(1f).setDuration(450)
                .setInterpolator(new OvershootInterpolator(3f)).start();
    }

    private class DragListener implements View.OnTouchListener {
        private final int slop = ViewConfiguration.get(PetService.this).getScaledTouchSlop();
        private final int longPressMs = ViewConfiguration.getLongPressTimeout();
        private float downRawX, downRawY;
        private int startX, startY;
        private boolean dragging, longPressed;
        private final Runnable longPress = () -> {
            longPressed = true;
            bounce();
            say(LONG_PRESS_LINES[random.nextInt(LONG_PRESS_LINES.length)]);
        };

        @Override public boolean onTouch(View v, MotionEvent e) {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downRawX = e.getRawX();
                    downRawY = e.getRawY();
                    startX = petParams.x;
                    startY = petParams.y;
                    dragging = false;
                    longPressed = false;
                    handler.postDelayed(longPress, longPressMs);
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    float dx = e.getRawX() - downRawX;
                    float dy = e.getRawY() - downRawY;
                    if (!dragging && (Math.abs(dx) > slop || Math.abs(dy) > slop)) {
                        dragging = true;
                        handler.removeCallbacks(longPress);
                    }
                    if (dragging || longPressed) {
                        petParams.x = startX + Math.round(dx);
                        petParams.y = startY + Math.round(dy);
                        clampToScreen();
                        wm.updateViewLayout(petView, petParams);
                        if (bubbleShown) positionBubble();
                    }
                    return true;
                }
                case MotionEvent.ACTION_UP:
                    handler.removeCallbacks(longPress);
                    if (!dragging && !longPressed) {
                        bounce();
                        say(TAP_LINES[random.nextInt(TAP_LINES.length)]);
                    }
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    handler.removeCallbacks(longPress);
                    return true;
            }
            return false;
        }
    }
}
@@END@@
cat > DeskPet/app/src/main/java/com/example/deskpet/MainActivity.java <<'@@END@@'
package com.example.deskpet;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

/** 设置页：授权悬浮窗、召唤/收起桌宠、调整大小。 */
public class MainActivity extends Activity {

    private TextView status;
    private Button grantBtn;

    private int dp(float v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private Button makeButton(String text, String colorHex) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextColor(Color.WHITE);
        b.setAllCaps(false);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor(colorHex));
        bg.setCornerRadius(dp(24));
        b.setBackground(bg);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(48));
        lp.topMargin = dp(12);
        b.setLayoutParams(lp);
        return b;
    }

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(24), dp(32), dp(24), dp(24));
        root.setBackgroundColor(Color.parseColor("#EEF5FD"));

        ImageView preview = new ImageView(this);
        preview.setImageResource(R.drawable.pet);
        preview.setAdjustViewBounds(true);
        preview.setLayoutParams(new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(260)));
        root.addView(preview);

        TextView title = new TextView(this);
        title.setText("鲸鲸女仆桌宠");
        title.setTextSize(22);
        title.setTextColor(Color.parseColor("#2B3A55"));
        title.setGravity(Gravity.CENTER);
        title.setPadding(0, dp(12), 0, dp(4));
        root.addView(title);

        status = new TextView(this);
        status.setTextSize(14);
        status.setTextColor(Color.parseColor("#5A6B86"));
        status.setGravity(Gravity.CENTER);
        root.addView(status);

        grantBtn = makeButton("① 授权“显示在其他应用上层”", "#7FA6D8");
        grantBtn.setOnClickListener(v -> startActivity(new Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName()))));
        root.addView(grantBtn);

        Button summon = makeButton("召唤桌宠", "#3E6FB0");
        summon.setOnClickListener(v -> {
            if (!Settings.canDrawOverlays(this)) {
                Toast.makeText(this, "请先授权悬浮窗权限", Toast.LENGTH_SHORT).show();
                return;
            }
            Intent i = new Intent(this, PetService.class);
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i); else startService(i);
        });
        root.addView(summon);

        Button dismiss = makeButton("收起桌宠", "#8C99AD");
        dismiss.setOnClickListener(v ->
                startService(new Intent(this, PetService.class).setAction(PetService.ACTION_STOP)));
        root.addView(dismiss);

        TextView sizeLabel = new TextView(this);
        sizeLabel.setTextColor(Color.parseColor("#2B3A55"));
        sizeLabel.setPadding(0, dp(20), 0, 0);
        root.addView(sizeLabel);

        final SharedPreferences sp = getSharedPreferences(PetService.PREFS, MODE_PRIVATE);
        int saved = sp.getInt(PetService.KEY_SIZE, PetService.DEFAULT_SIZE);
        sizeLabel.setText("大小：" + saved + "%");
        SeekBar seek = new SeekBar(this);
        seek.setMax(100);                 // 50% ~ 150%
        seek.setProgress(saved - 50);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean fromUser) {
                sizeLabel.setText("大小：" + (p + 50) + "%");
            }
            @Override public void onStartTrackingTouch(SeekBar s) { }
            @Override public void onStopTrackingTouch(SeekBar s) {
                sp.edit().putInt(PetService.KEY_SIZE, s.getProgress() + 50).apply();
                if (Settings.canDrawOverlays(MainActivity.this)) {
                    Intent i = new Intent(MainActivity.this, PetService.class)
                            .setAction(PetService.ACTION_RESIZE);
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i); else startService(i);
                }
            }
        });
        root.addView(seek);

        TextView tips = new TextView(this);
        tips.setTextSize(12);
        tips.setTextColor(Color.parseColor("#7C8AA3"));
        tips.setPadding(0, dp(20), 0, 0);
        tips.setText("玩法：拖动移动位置 · 单击说话 · 长按撒娇\n"
                + "小米/OPPO/vivo/华为等系统如果桌宠被自动关闭，请在系统设置里给本应用开启“自启动”“后台弹出界面”，并把电池策略设为“无限制”。");
        root.addView(tips);

        ScrollView sv = new ScrollView(this);
        sv.setFillViewport(true);
        sv.addView(root);
        setContentView(sv);

        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
    }

    @Override protected void onResume() {
        super.onResume();
        boolean ok = Settings.canDrawOverlays(this);
        status.setText(ok ? "悬浮窗权限已开启，点击“召唤桌宠”吧~" : "还需要授权悬浮窗权限才能显示桌宠");
        grantBtn.setVisibility(ok ? View.GONE : View.VISIBLE);
    }
}
@@END@@
PNG=$(ls *.png | head -1)
cp "$PNG" DeskPet/app/src/main/res/drawable-nodpi/pet.png
pip install pillow >/dev/null 2>&1 || true
PNG="$PNG" python3 - <<'@@END@@'
import os
from PIL import Image
im=Image.open(os.environ["PNG"]).convert("RGBA")
w,h=im.size
head=im.crop((0,0,w,int(h*0.30)))
s=max(head.size)
c=Image.new("RGBA",(s,s),(0,0,0,0))
c.paste(head,((s-head.width)//2,(s-head.height)//2))
c=c.resize((192,192))
b=Image.new("RGBA",(192,192),(214,232,250,255))
b.alpha_composite(c)
b.save("DeskPet/app/src/main/res/drawable-nodpi/ic_launcher.png")
@@END@@
