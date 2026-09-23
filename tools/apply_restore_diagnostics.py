#!/usr/bin/env python3
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "lib/services/resonate_diagnostics.dart"

EXPORT_OLD = """  static Future<String?> exportReport() async {
    final report = await snapshot();
    final json = const JsonEncoder.withIndent('  ').convert(report);
    final directory = await _documentsDirectory();
    if (directory == null) throw StateError('Could not access a local Documents directory.');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'resonate-diagnostics-$stamp.json';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(json, flush: true);

    if (!Platform.isAndroid) {
      await record('report_exported_local', {
        'eventCount': (report['events'] as List).length,
        'crashCount': (report['crashes'] as List).length,
        'feedbackCount': (report['feedback'] as List).length,
        'path': file.path,
      });
      return file.path;
    }

    try {
      final savedUri = await _mediaStoreChannel.invokeMethod<String>('saveDiagnosticReport', {
        'fileName': fileName,
        'bytes': Uint8List.fromList(utf8.encode(json)),
      });
      if (savedUri == null || savedUri.isEmpty) {
        await record('report_save_cancelled', {'fileName': fileName});
        return null;
      }
      await record('report_saved_to_device', {
        'uri': savedUri,
        'suggestedFileName': fileName,
        'eventCount': (report['events'] as List).length,
        'crashCount': (report['crashes'] as List).length,
        'feedbackCount': (report['feedback'] as List).length,
      });
      return savedUri;
    } on PlatformException catch (e) {
      await record('report_device_save_failed', {'code': e.code, 'message': e.message});
      rethrow;
    } catch (e) {
      await record('report_device_save_failed', {'error': e.toString()});
      rethrow;
    }
  }"""

def main() -> int:
    text = ""
    for rev in ["34e13570cb", "fee20c5751", "d3f97e3123", "HEAD~3", "HEAD~8", "HEAD~15"]:
        try:
            raw = subprocess.check_output(
                ["git", "show", f"{rev}:lib/services/resonate_diagnostics.dart"],
                cwd=ROOT,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            continue
        if b"PLACEHOLDER" in raw or b"class ResonateDiagnostics" not in raw:
            continue
        text = raw.decode("utf-8")
        print("found good at", rev, len(text))
        break
    if not text:
        cur = OUT.read_text() if OUT.exists() else ""
        if "class ResonateDiagnostics" in cur and "PLACEHOLDER" not in cur:
            text = cur
            print("using current")
        else:
            print("FAILED restore")
            return 1

    text = text.replace(
        "MethodChannel('com.example.resonate/media_store')",
        "MethodChannel('com.aetherion.resonate/media_store')",
    )

    export_new_path = Path(__file__).with_name("frag_export_new.dart.txt")
    if export_new_path.exists() and EXPORT_OLD in text:
        text = text.replace(EXPORT_OLD, export_new_path.read_text(), 1)
        print("export function replaced")
    else:
        print("export replace skipped; channel_ok=", "com.aetherion.resonate/media_store" in text)

    OUT.write_text(text)
    print("wrote", OUT.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
