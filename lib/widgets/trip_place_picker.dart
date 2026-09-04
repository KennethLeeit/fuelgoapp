import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trip_models.dart';
import '../services/trip_location_service.dart';
import '../theme/app_theme.dart';

class TripPlacePicker extends StatefulWidget {
  final String label;
  final String hint;
  final TripPlace? value;
  final TripLocationService service;
  final ValueChanged<TripPlace?> onChanged;
  final bool enabled;

  const TripPlacePicker({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.service,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<TripPlacePicker> createState() => _TripPlacePickerState();
}

class _TripPlacePickerState extends State<TripPlacePicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<TripPlace> _results = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    final request = ++_request;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final places = await widget.service.searchPlaces(trimmed);
        if (!mounted || request != _request) return;
        setState(() {
          _results = places;
          _error = places.isEmpty ? 'No Malaysian locations found.' : null;
        });
      } on TripLocationException catch (error) {
        if (mounted && request == _request) {
          setState(() {
            _results = const [];
            _error = error.message;
          });
        }
      } finally {
        if (mounted && request == _request) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined,
                color: AppColors.primaryBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGrey)),
                  Text(widget.value!.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (widget.value!.address != widget.value!.name)
                    Text(widget.value!.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGrey)),
                ],
              ),
            ),
            if (widget.enabled)
              IconButton(
                tooltip: 'Change ${widget.label.toLowerCase()}',
                onPressed: () {
                  _controller.clear();
                  widget.onChanged(null);
                },
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          enabled: widget.enabled,
          controller: _controller,
          focusNode: _focus,
          onChanged: _search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(_error!,
                style: const TextStyle(fontSize: 11, color: Colors.red)),
          ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: _results
                  .map((place) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, size: 20),
                        title: Text(place.name),
                        subtitle: Text(place.address,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          _focus.unfocus();
                          setState(() => _results = const []);
                          widget.onChanged(place);
                        },
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
