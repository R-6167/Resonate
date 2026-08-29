diff --git a/lib/screens/home_screen.dart b/lib/screens/home_screen.dart
index 0000000..0000000 100644
--- a/lib/screens/home_screen.dart
+++ b/lib/screens/home_screen.dart
@@
-          _PlaybackBar(),
+          GestureDetector(
+            onTap: () {
+              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
+            },
+            child: _PlaybackBar(),
+          ),
         ],
       ),
