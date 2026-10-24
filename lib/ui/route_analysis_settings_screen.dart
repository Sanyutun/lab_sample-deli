import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_services.dart';
import '../domain/ids.dart';
import '../domain/route_analysis.dart';
import 'common.dart';
import 'zone_map.dart';

/// Admin: where the office is and the circular distance zones measured from
/// it. Everything here is a draft until SAVE is pressed, and a draft that
/// would leave a gap or an overlap in the zones is refused with the reason —
/// no GPS record is ever touched by this screen.
class RouteAnalysisSettingsScreen extends StatefulWidget {
  const RouteAnalysisSettingsScreen({super.key});

  @override
  State<RouteAnalysisSettingsScreen> createState() =>
      _RouteAnalysisSettingsScreenState();
}

/// Colours the zones may display in; enough to tell the rings apart without
/// a full colour picker.
const List<(String, int)> zoneColorChoices = [
  ('Green', 0xFF2E7D32),
  ('Amber', 0xFFF9A825),
  ('Orange', 0xFFEF6C00),
  ('Red', 0xFFC62828),
  ('Blue', 0xFF1565C0),
  ('Purple', 0xFF6A1B9A),
  ('Teal', 0xFF00695C),
  ('Grey', 0xFF546E7A),
];

class _RouteAnalysisSettingsScreenState
    extends State<RouteAnalysisSettingsScreen> {
  final MapController _map = MapController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _lat = TextEditingController();
  final TextEditingController _lng = TextEditingController();

  List<DistanceZone> _zones = defaultZones;
  bool _mapReady = false;
  bool _loaded = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Screen-lifetime controllers, unlike dialog ones, are safe to dispose.
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    _isAdmin = services.auth.isAdmin;
    final name = await services.settings.get(officeNameSettingKey);
    final lat = await services.settings.get(centreLatSettingKey);
    final lng = await services.settings.get(centreLngSettingKey);
    final zones = zonesFromJson(await services.settings.get(zonesSettingKey));
    if (!mounted) return;
    setState(() {
      _name.text = name ?? '';
      _lat.text = lat ?? '';
      _lng.text = lng ?? '';
      _zones = zones;
      _loaded = true;
    });
  }

  /// The typed coordinates, or null while they are incomplete/invalid.
  LatLng? get _draftCentre {
    final la = double.tryParse(_lat.text.trim());
    final lo = double.tryParse(_lng.text.trim());
    return validCoordinates(la, lo) ? LatLng(la!, lo!) : null;
  }

  /// Everything that must be true before SAVE is allowed.
  List<String> get _errors {
    final errors = validateZones(_zones);
    if (_name.text.trim().isEmpty) {
      errors.insert(0, 'The office / laboratory name is required.');
    }
    if (_draftCentre == null) {
      errors.insert(
        0,
        'Enter the office latitude (-90 to 90) and longitude '
        '(-180 to 180).',
      );
    }
    return errors;
  }

  List<DistanceZone> get _sorted =>
      [..._zones]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// "Test": frames the typed centre on the preview map so the admin can see
  /// it really is the shop before saving.
  void _previewCentre() {
    final draft = _draftCentre;
    if (draft == null || !_mapReady) {
      showMessage(context, 'Enter valid coordinates first.', error: true);
      return;
    }
    _map.move(draft, 16);
  }

  Future<void> _save() async {
    final services = AppScope.of(context);
    final centre = _draftCentre;
    if (centre == null) return;
    await services.settings.set(officeNameSettingKey, _name.text.trim());
    await services.settings.set(
      centreLatSettingKey,
      centre.latitude.toString(),
    );
    await services.settings.set(
      centreLngSettingKey,
      centre.longitude.toString(),
    );
    await services.settings.set(zonesSettingKey, zonesToJson(_zones));
    if (!mounted) return;
    showMessage(
      context,
      'Saved. Distances and zone assignments now use this configuration.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return PageScaffold(
        title: 'Route Analysis Settings',
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return PageScaffold(
        title: 'Route Analysis Settings',
        body: const EmptyState(message: 'Only an admin can change these.'),
      );
    }
    final errors = _errors;
    return PageScaffold(
      title: 'Route Analysis Settings',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.icon(
            onPressed: errors.isEmpty ? _save : null,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('SAVE'),
          ),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _officeCard(),
          const SizedBox(height: 12),
          _zonesCard(errors),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- office ----

  Widget _officeCard() {
    final draft = _draftCentre;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Office / laboratory',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'The centre every route distance and zone ring is measured '
              'from — the office\'s own location, never the phone\'s.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Office / laboratory name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _previewMap(draft),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _previewCentre,
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Test centre'),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tap the map to pick the centre; Test frames it.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewMap(LatLng? draft) {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        // Yangon only as a starting view until the office itself is set.
        initialCenter: draft ?? const LatLng(16.8699, 96.1647),
        initialZoom: draft == null ? 5 : 15,
        onMapReady: () => _mapReady = true,
        onTap: (tap, position) => setState(() {
          _lat.text = position.latitude.toStringAsFixed(6);
          _lng.text = position.longitude.toStringAsFixed(6);
        }),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'lab_commission',
        ),
        if (draft != null) ...zoneLayers(centre: draft, zones: _zones),
        if (draft != null)
          MarkerLayer(
            markers: [
              Marker(
                point: draft,
                width: 36,
                height: 36,
                child: const Tooltip(
                  message: 'Office centre',
                  child: Icon(Icons.place, size: 30, color: Colors.red),
                ),
              ),
            ],
          ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  // ---- zones ----

  Widget _zonesCard(List<String> errors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Distance zones',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'A route belongs to the zone that holds its farthest point. '
              'Each zone includes its lower edge and excludes its upper one; '
              'the last zone is open-ended.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  errors.join('\n'),
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            for (final zone in _sorted) _zoneTile(zone),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _addZone,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add zone'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneTile(DistanceZone zone) {
    final sorted = _sorted;
    final index = sorted.indexWhere((z) => z.id == zone.id);
    return ListTile(
      dense: true,
      leading: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: zoneColor(zone),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(zone.name),
      subtitle: Text(zone.rangeLabel, style: const TextStyle(fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            tooltip: 'Move up',
            visualDensity: VisualDensity.compact,
            onPressed: index <= 0 ? null : () => _move(zone, -1),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 16),
            tooltip: 'Move down',
            visualDensity: VisualDensity.compact,
            onPressed: index < 0 || index >= sorted.length - 1
                ? null
                : () => _move(zone, 1),
          ),
          Switch(
            value: zone.enabled,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => setState(
              () => _zones = [
                for (final z in _zones)
                  z.id == zone.id ? z.copyWith(enabled: v) : z,
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Edit zone',
            visualDensity: VisualDensity.compact,
            onPressed: () => _editZone(zone),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Delete zone',
            visualDensity: VisualDensity.compact,
            onPressed: () => _deleteZone(zone),
          ),
        ],
      ),
    );
  }

  void _move(DistanceZone zone, int direction) {
    final sorted = _sorted;
    final index = sorted.indexWhere((z) => z.id == zone.id);
    final other = index + direction;
    if (other < 0 || other >= sorted.length) return;
    setState(() {
      _zones = [
        for (final z in _zones)
          if (z.id == sorted[index].id)
            z.copyWith(sortOrder: sorted[other].sortOrder)
          else if (z.id == sorted[other].id)
            z.copyWith(sortOrder: sorted[index].sortOrder)
          else
            z,
      ];
    });
  }

  Future<void> _deleteZone(DistanceZone zone) async {
    final ok = await confirmDialog(
      context,
      'Delete ${zone.name}?',
      'Distances it covered will fall into the neighbouring zone. '
          'GPS records are not touched.',
      actionLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    setState(() => _zones = withoutZone(_zones, zone));
  }

  Future<void> _addZone() async {
    // The new zone starts where the current last band ends.
    final sorted = _sorted;
    final last = sorted.isEmpty ? null : sorted.last;
    await _editZone(
      DistanceZone(
        id: newId('zone'),
        name: '',
        minKm: last == null ? 0 : (last.maxKm ?? last.minKm + 1),
        maxKm: null,
        argb: zoneColorChoices.first.$2,
        sortOrder: (sorted.isEmpty ? 0 : sorted.last.sortOrder) + 1,
      ),
      isNew: true,
    );
  }

  /// Creates or edits one zone and applies the result at once; a boundary
  /// that moved takes the neighbouring zone with it so the bands stay joined.
  /// Controllers are deliberately not disposed after the dialog closes —
  /// disposal races the dialog's exit rebuild (see the delivery-routes
  /// dialogs).
  Future<void> _editZone(DistanceZone zone, {bool isNew = false}) async {
    final name = TextEditingController(text: zone.name);
    final min = TextEditingController(text: trimKm(zone.minKm));
    final max = TextEditingController(
      text: zone.maxKm == null ? '' : trimKm(zone.maxKm!),
    );
    var argb = zone.argb;
    final edited = await showDialog<DistanceZone>(
      context: context,
      builder: (dialogCtx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void save() {
              final newName = name.text.trim();
              final newMin = double.tryParse(min.text.trim());
              final rawMax = max.text.trim();
              final newMax = rawMax.isEmpty ? null : double.tryParse(rawMax);
              if (newName.isEmpty) {
                setDialogState(() => error = 'Give the zone a name.');
                return;
              }
              if (newMin == null || newMin < 0) {
                setDialogState(() {
                  error = 'Minimum distance must be 0 or more.';
                });
                return;
              }
              if (newMax != null && newMax <= newMin) {
                setDialogState(() {
                  error =
                      'Maximum must be greater than the minimum '
                      '(leave it empty for the open-ended zone).';
                });
                return;
              }
              Navigator.pop(
                dialogCtx,
                zone.copyWith(
                  name: newName,
                  minKm: newMin,
                  maxKm: newMax,
                  argb: argb,
                  clearMax: newMax == null,
                ),
              );
            }

            return AlertDialog(
              title: Text(isNew ? 'Add zone' : 'Edit ${zone.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Zone name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: min,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Min km (included)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: max,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Max km (excluded)',
                            hintText: 'empty = open-ended',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: argb,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Colour',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final choice in zoneColorChoices)
                        DropdownMenuItem(
                          value: choice.$2,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Color(choice.$2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(choice.$1),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => argb = v ?? argb),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(onPressed: save, child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
    if (edited == null || !mounted) return;
    setState(() {
      _zones = isNew
          ? [..._zones, edited]
          : movedZoneBoundary(_zones, before: zone, after: edited);
    });
  }
}
