import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../scan/scan_screen.dart';

/// ID entry with Look up + Scan ID, shared by the check-in and mobilize flows.
class IdEntry extends StatelessWidget {
  final TextEditingController controller;
  final Color color;
  final bool busy;
  final VoidCallback onLookup;
  final VoidCallback onChanged;
  const IdEntry(
      {super.key,
      required this.controller,
      required this.color,
      required this.busy,
      required this.onLookup,
      required this.onChanged});

  Future<void> _scan(BuildContext context) async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (id != null) {
      controller.text = id;
      onChanged();
      onLookup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Find a voter',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Scanning is the fast path in a queue; typing is the fallback.
        Material(
          color: color,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const Key('scan-id'),
            borderRadius: BorderRadius.circular(18),
            onTap: busy ? null : () => _scan(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.document_scanner_outlined, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Scan ID card',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('Front or back — reads the ID number',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Row(children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('or type it', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
          Expanded(child: Divider()),
        ]),
        const SizedBox(height: 14),
        TextField(
          key: const Key('id-input'),
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
          style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'ID number',
            prefixIcon: Icon(Icons.badge_outlined, color: color),
          ),
          textInputAction: TextInputAction.search,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onLookup(),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('lookup'),
          style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color, width: 1.4)),
          icon: busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : const Icon(Icons.search),
          label: Text(busy ? 'Looking up…' : 'Look up'),
          onPressed: busy ? null : onLookup,
        ),
      ]),
    );
  }
}

/// Voter summary card shown after a successful register match.
class VoterCard extends StatelessWidget {
  final Voter voter;
  final Color color, soft;
  final bool? inRegion;
  const VoterCard({super.key, required this.voter, required this.color, required this.soft, this.inRegion});

  @override
  Widget build(BuildContext context) {
    final v = voter;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: color,
          child: Text(initials(v.name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(['ID ${v.nationalId}', v.sexLabel, if (v.dob.isNotEmpty) '${v.age} yrs'].join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (v.area.isNotEmpty) Text(v.area, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              if (v.idOnly) ...[
                Pill('ID VERIFIED', fg: color, bg: Colors.white),
                const Pill('NOT ON VOTER REGISTER', fg: Color(0xFFB45309), bg: Color(0xFFFFF7E6)),
              ] else
                Pill('REGISTERED VOTER', fg: color, bg: Colors.white),
              if (inRegion != null) RegionPill(inRegion!),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Controllers for details the operator types when the voter isn't in the register
/// (or when they override the registered location).
class PersonFields {
  final name = TextEditingController();
  final dob = TextEditingController();
  final phone = TextEditingController();
  final county = TextEditingController();
  final constituency = TextEditingController();
  final ward = TextEditingController();
  String? sex;

  void clear() {
    for (final c in [name, dob, phone, county, constituency, ward]) {
      c.clear();
    }
    sex = null;
  }

  void dispose() {
    for (final c in [name, dob, phone, county, constituency, ward]) {
      c.dispose();
    }
  }

  Map<String, String?> toJson({required bool identity, required bool location}) => {
        'phone': phone.text,
        if (identity) ...{'name': name.text, 'sex': sex, 'dob': dob.text},
        if (location) ...{'county': county.text, 'constituency': constituency.text, 'ward': ward.text},
      };
}

class IdentityInputs extends StatefulWidget {
  final PersonFields f;

  /// Offline the server fills blanks from the register at sync time, so fields become optional.
  final bool required;
  const IdentityInputs(this.f, {super.key, this.required = true});
  @override
  State<IdentityInputs> createState() => _IdentityInputsState();
}

class _IdentityInputsState extends State<IdentityInputs> {
  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return Column(children: [
      TextFormField(
        controller: f.name,
        decoration: InputDecoration(labelText: widget.required ? 'Full name' : 'Full name (optional)'),
        validator: (v) => widget.required && (v ?? '').trim().isEmpty ? 'Required' : null,
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: f.sex,
            decoration: const InputDecoration(labelText: 'Sex'),
            items: const [
              DropdownMenuItem(value: 'F', child: Text('Female')),
              DropdownMenuItem(value: 'M', child: Text('Male')),
            ],
            onChanged: (v) => setState(() => f.sex = v),
            validator: (v) => widget.required && v == null ? 'Required' : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: f.dob,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Date of birth'),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime(1990),
                firstDate: DateTime(1900),
                lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
              );
              if (d != null) f.dob.text = d.toIso8601String().substring(0, 10);
            },
          ),
        ),
      ]),
    ]);
  }
}

class LocationInputs extends StatelessWidget {
  final PersonFields f;
  final bool required;
  const LocationInputs(this.f, {super.key, this.required = true});

  @override
  Widget build(BuildContext context) {
    String? req(String? v) => required && (v ?? '').trim().isEmpty ? 'Required' : null;
    return Column(children: [
      TextFormField(controller: f.county, decoration: const InputDecoration(labelText: 'County'), validator: req),
      const SizedBox(height: 10),
      TextFormField(
          controller: f.constituency, decoration: const InputDecoration(labelText: 'Constituency'), validator: req),
      const SizedBox(height: 10),
      TextFormField(controller: f.ward, decoration: const InputDecoration(labelText: 'Ward'), validator: req),
    ]);
  }
}
