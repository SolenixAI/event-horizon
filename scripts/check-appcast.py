#!/usr/bin/env python3
"""Fail unless the generated Sparkle feed contains the exact release item."""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("appcast")
	parser.add_argument("--short-version", required=True)
	parser.add_argument("--version", required=True)
	parser.add_argument("--url", required=True)
	parser.add_argument("--ed-signature", required=True)
	parser.add_argument("--length", required=True)
	parser.add_argument("--min-system", default="26.0")
	args = parser.parse_args()

	root = ET.parse(args.appcast).getroot()
	channel = root.find("channel")
	if channel is None:
		parser.error("appcast has no <channel>")
	items = [
		item for item in channel.findall("item")
		if item.findtext(f"{{{SPARKLE}}}shortVersionString") == args.short_version
		and item.findtext(f"{{{SPARKLE}}}version") == args.version
	]
	if len(items) != 1:
		parser.error("appcast must contain exactly one item for this short and build version")

	item = items[0]
	enclosure = item.find("enclosure")
	actual = {
		"title": item.findtext("title"),
		"description": item.findtext("description"),
		"minimum system": item.findtext(f"{{{SPARKLE}}}minimumSystemVersion"),
		"download URL": enclosure.get("url") if enclosure is not None else None,
		"EdDSA signature": enclosure.get(f"{{{SPARKLE}}}edSignature") if enclosure is not None else None,
		"archive length": enclosure.get("length") if enclosure is not None else None,
	}
	expected = {
		"title": args.short_version,
		"description": None,
		"minimum system": args.min_system,
		"download URL": args.url,
		"EdDSA signature": args.ed_signature,
		"archive length": args.length,
	}
	if not actual["description"]:
		parser.error("release item has no changelog description")
	for name, value in expected.items():
		if name != "description" and actual[name] != value:
			parser.error(f"{name} mismatch: expected {value!r}, got {actual[name]!r}")
	try:
		if int(actual["archive length"]) <= 0:
			raise ValueError
	except (TypeError, ValueError):
		parser.error("archive length must be a positive integer")

	print(f"Appcast metadata validated for {args.short_version} ({args.version}).")


if __name__ == "__main__":
	main()
