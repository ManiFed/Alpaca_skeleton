// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const _viewType = 'ttn-aladin-sky';
bool _registered = false;

class AladinSky extends StatefulWidget {
  const AladinSky({
    super.key,
    this.ra,
    this.dec,
    this.fov = 65,
    this.targetLabel,
    this.drift = true,
  });

  final double? ra;
  final double? dec;
  final double fov;
  final String? targetLabel;
  final bool drift;

  @override
  State<AladinSky> createState() => _AladinSkyState();
}

class _AladinSkyState extends State<AladinSky> {
  @override
  void initState() {
    super.initState();
    if (!_registered) {
      _registered = true;
      _ensureControllerScript();
      ui_web.platformViewRegistry.registerViewFactory(_viewType, _buildElement);
    }
  }

  @override
  void didUpdateWidget(covariant AladinSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_viewId != null) _configure(_viewId!);
  }

  int? _viewId;

  void _onPlatformViewCreated(int id) {
    _viewId = id;
    _configure(id);
  }

  void _configure(int id) {
    final config = <String, Object?>{
      'ra': widget.ra,
      'dec': widget.dec,
      'fov': widget.fov,
      'targetLabel': widget.targetLabel,
      'drift': widget.drift,
    };
    js_util.callMethod<void>(
      html.window,
      '__ttnConfigureAladinSky',
      [id, js_util.jsify(config)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: _viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}

html.Element _buildElement(int id) {
  final container = html.DivElement()
    ..className = 'ttn-sky'
    ..style.cssText =
        'width:100%;height:100%;position:absolute;top:0;left:0;pointer-events:none;';

  final sky = html.DivElement()
    ..id = 'ttn-sky-$id'
    ..style.cssText = 'width:100%;height:100%;';

  container.append(sky);

  html.document.head!.append(html.ScriptElement()..text = _initScript(id));

  return container;
}

void _ensureControllerScript() {
  if (html.document.getElementById('ttn-aladin-controller') != null) return;
  html.document.head!.append(
    html.ScriptElement()
      ..id = 'ttn-aladin-controller'
      ..text = _controllerScript,
  );
}

const _controllerScript = '''
(function() {
  window.__ttnAladinSky = window.__ttnAladinSky || {};

  window.__ttnConfigureAladinSky = function(id, config) {
    var entry = window.__ttnAladinSky[id] || {};
    entry.config = config || {};
    window.__ttnAladinSky[id] = entry;
    if (entry.applyConfig) entry.applyConfig();
  };
})();
''';

String _initScript(int id) => '''
(function() {
  var divId = 'ttn-sky-$id';
  var entry = window.__ttnAladinSky[$id] || {};
  window.__ttnAladinSky[$id] = entry;

  function init() {
    if (typeof A === 'undefined' || !A.init) { setTimeout(init, 200); return; }
    A.init.then(function() {
      var el = document.getElementById(divId);
      if (!el) return;
      var aladin = A.aladin('#' + divId, {
        survey: 'P/DSS2/color',
        fov: 65,
        cooFrame: 'ICRS',
        showReticle: false,
        showZoomControl: false,
        showFullscreenControl: false,
        showLayersControl: false,
        showGotoControl: false,
        showShareControl: false,
        showSimbadPointerControl: false,
        showCooGrid: false,
        showFrame: false,
        showContextMenu: false,
        showStatusBar: false,
        showProjectionControl: false,
        showCooGridControl: false,
      });
      var markerCatalog = A.catalog({name: 'Target', sourceSize: 12});
      aladin.addCatalog(markerCatalog);
      var driftTimer = null;

      entry.aladin = aladin;
      entry.applyConfig = function() {
        var config = entry.config || {};
        var ra = typeof config.ra === 'number' ? config.ra : Math.random() * 360;
        var dec = typeof config.dec === 'number' ? config.dec : (Math.random() - 0.5) * 60;
        var fov = typeof config.fov === 'number' ? config.fov : 65;
        var label = config.targetLabel || 'Target';

        if (driftTimer) {
          clearInterval(driftTimer);
          driftTimer = null;
        }

        aladin.setFoV(fov);
        aladin.gotoRaDec(ra, dec);
        markerCatalog.removeAll();
        if (typeof config.ra === 'number' && typeof config.dec === 'number') {
          markerCatalog.addSources([A.marker(ra, dec, {popupTitle: label})]);
        }

        if (config.drift !== false && typeof config.ra !== 'number') {
          driftTimer = setInterval(function() {
            ra += 0.05;
            if (ra >= 360) ra -= 360;
            aladin.gotoRaDec(ra, dec);
          }, 100);
        }
      };
      entry.applyConfig();
    }).catch(function() {});
  }
  init();
})();
''';
