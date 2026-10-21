import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../theme/os_ui.dart';

class OsDatingFeaturesScreen extends StatefulWidget {
  const OsDatingFeaturesScreen({super.key});

  @override
  State<OsDatingFeaturesScreen> createState() => _OsDatingFeaturesScreenState();
}

class _OsDatingFeaturesScreenState extends State<OsDatingFeaturesScreen> {
  final _cityController = TextEditingController();
  Map<String, dynamic> _prefs = {};
  List<dynamic> _prompts = [];
  String _category = 'naija';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrompts();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Api.featurePreferences();
      if (!mounted) return;
      setState(() {
        _prefs = data;
        _cityController.text = (data['preferred_city'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your settings. Check your connection and try again.';
      });
    }
  }

  Future<void> _loadPrompts() async {
    try {
      final items = await Api.icebreakers(category: _category);
      if (!mounted) return;
      setState(() => _prompts = items);
    } catch (_) {
      if (mounted) setState(() => _prompts = _fallbackPrompts);
    }
  }

  static const Map<String, String> _intentionLabels = {
    'serious_relationship': 'Serious relationship',
    'marriage_minded': 'Marriage-minded',
    'casual_dating': 'Casual dating',
    'friendship': 'Friendship first',
  };

  static const List<String> _fallbackPrompts = [
    "What's your idea of a peaceful relationship?",
    "Sunday rice or Saturday jollof — and why?",
    "What's a green flag you notice quickly?",
    "What's your ideal low-budget date?",
  ];

  Future<void> _save(Map<String, dynamic> changes, {String? busyKey}) async {
    final previous = Map<String, dynamic>.from(_prefs);
    if (busyKey != null) setState(() { _busy.add(busyKey); _prefs.addAll(changes); });
    try {
      final updated = await Api.updateFeaturePreferences(changes);
      if (!mounted) return;
      setState(() {
        _prefs = updated;
        _cityController.text = (updated['preferred_city'] ?? '').toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your preferences have been saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      if (busyKey != null) setState(() => _prefs = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save settings. ${Api.friendlyError(e)}')),
      );
    } finally {
      if (mounted && busyKey != null) setState(() => _busy.remove(busyKey));
    }
  }

  Widget _section(String title, String subtitle, IconData icon, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: OsColors.purple, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: OsColors.muted, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _toggle(String key, String title, String subtitle, {bool invert = false}) {
    final value = _prefs[key] == true;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: OsColors.muted, fontSize: 12)),
      value: value,
      onChanged: _busy.contains(key) ? null : (next) => _save({key: next}, busyKey: key),
    );
  }

  Widget _dropdown(String key, String label, List<DropdownMenuItem<String>> items) {
    final current = (_prefs[key] ?? '').toString();
    final valid = items.any((item) => item.value == current);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: valid ? current : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: items,
        onChanged: _saving ? null : (value) {
          if (value != null) _save({key: value});
        },
      ),
    );
  }

  List<DropdownMenuItem<String>> _options(List<(String, String)> values) =>
      values.map((e) => DropdownMenuItem<String>(value: e.$1, child: Text(e.$2))).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dating preferences')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_rounded, size: 42),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('Try again')),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section('Your visibility', 'You decide who can discover and contact you.', Icons.visibility_outlined, [
                      _toggle('discoverable', 'Show me in discovery', 'Turn this off to stop appearing in discovery.'),
                      _toggle('private_mode', 'Private mode', 'Removes your profile from discovery while enabled.'),
                      _toggle('show_online_status', 'Show online status', 'Let other members see your online status when supported.'),
                      _toggle('allow_messages_from_matches', 'Allow messages from matches', 'Preference saved to your account. Existing server chat permissions still apply.'),
                    ]),
                    _section('Who you want to meet', 'Use these preferences to shape your discovery feed.', Icons.favorite_border_rounded, [
                      _dropdown('relationship_intention', 'Relationship intention', _options(const [
                        ('serious_relationship', 'Serious relationship'),
                        ('marriage_minded', 'Marriage-minded'),
                        ('casual_dating', 'Casual dating'),
                        ('friendship', 'Friendship first'),
                      ])),
                      TextField(
                        controller: _cityController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Preferred city or area',
                          hintText: 'e.g. Warri, Benin City, Lagos',
                          border: OutlineInputBorder(),
                          helperText: 'This is a preference, not your live location.',
                        ),
                        onSubmitted: (value) => _save({'preferred_city': value.trim()}),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Expanded(child: Text('Maximum distance', style: TextStyle(fontWeight: FontWeight.w700))),
                        Text('${_prefs['max_distance_km'] ?? 100} km', style: const TextStyle(color: OsColors.purple, fontWeight: FontWeight.w800)),
                      ]),
                      Slider(
                        min: 1, max: 500, divisions: 49,
                        value: ((_prefs['max_distance_km'] as num?)?.toDouble() ?? 100).clamp(1, 500).toDouble(),
                        label: '${_prefs['max_distance_km'] ?? 100} km',
                        onChanged: (value) => setState(() => _prefs['max_distance_km'] = value.round()),
                        onChangeEnd: (value) => _save({'max_distance_km': value.round()}),
                      ),
                    ]),
                    _section('Lifestyle & values', 'Optional details to help find people with similar priorities.', Icons.tune_rounded, [
                      _dropdown('faith_preference', 'Faith preference', _options(const [
                        ('', 'No preference / prefer not to say'),
                        ('christian', 'Christian'),
                        ('muslim', 'Muslim'),
                        ('traditional', 'Traditional beliefs'),
                        ('other', 'Other'),
                      ])),
                      _dropdown('wants_children', 'Children', _options(const [
                        ('', 'Prefer not to say'),
                        ('wants_children', 'Wants children'),
                        ('does_not_want_children', 'Does not want children'),
                        ('has_children', 'Has children'),
                        ('open_to_discussion', 'Open to discussion'),
                      ])),
                      _dropdown('smoking_preference', 'Smoking', _options(const [
                        ('', 'No preference / prefer not to say'),
                        ('never', 'Does not smoke'),
                        ('sometimes', 'Smokes sometimes'),
                        ('smoker', 'Smokes'),
                      ])),
                      _dropdown('drinking_preference', 'Alcohol', _options(const [
                        ('', 'No preference / prefer not to say'),
                        ('never', 'Does not drink'),
                        ('sometimes', 'Drinks sometimes'),
                        ('drinks', 'Drinks'),
                      ])),
                      _dropdown('family_values', 'Family involvement', _options(const [
                        ('', 'Prefer not to say'),
                        ('very_important', 'Very important'),
                        ('important', 'Important'),
                        ('independent', 'Prefer more independence'),
                        ('open_to_discussion', 'Open to discussion'),
                      ])),
                    ]),
                    _section('Naija Icebreakers', 'Conversation starters for when you match.', Icons.forum_outlined, [
                      DropdownButtonFormField<String>(
                        value: _category,
                        decoration: const InputDecoration(labelText: 'Prompt style', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'naija', child: Text('Naija')),
                          DropdownMenuItem(value: 'pidgin', child: Text('Nigerian Pidgin')),
                          DropdownMenuItem(value: 'getting_to_know_you', child: Text('Get to know you')),
                          DropdownMenuItem(value: 'values', child: Text('Values & relationships')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _category = value);
                            _loadPrompts();
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      for (final prompt in _prompts)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: OsColors.bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(prompt.toString()),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _loadPrompts,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Change prompts'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    Text(
                      'OS shows verification badges only for statuses confirmed by the server. Never send money or verification codes to someone you have just met.',
                      style: TextStyle(color: OsColors.muted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
    );
  }
}
