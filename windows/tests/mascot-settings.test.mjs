import { test } from "node:test";
import assert from "node:assert/strict";
import { MascotSettingsManager } from "../src/mascot/settings.ts";

test("MascotSettingsManager default & corrupt fallback", () => {
  const mockStorage = new Map();
  const storage = {
    getItem: (k) => mockStorage.get(k) ?? null,
    setItem: (k, v) => mockStorage.set(k, String(v)),
  };

  assert.equal(MascotSettingsManager.getSelectedMascot(storage), "shapeshifter");
  MascotSettingsManager.setSelectedMascot("mochi", storage);
  assert.equal(MascotSettingsManager.getSelectedMascot(storage), "mochi");

  // Corrupt string test
  storage.setItem("coucou_selected_mascot", "invalid_value");
  assert.equal(MascotSettingsManager.getSelectedMascot(storage), "shapeshifter");

  storage.setItem("coucou_selected_mascot", "");
  assert.equal(MascotSettingsManager.getSelectedMascot(storage), "shapeshifter");

  // Shape tests
  assert.equal(MascotSettingsManager.getShape(storage), "squircle");
  MascotSettingsManager.setShape("orb", storage);
  assert.equal(MascotSettingsManager.getShape(storage), "orb");
  storage.setItem("coucou_mascot_shape", "invalid_shape");
  assert.equal(MascotSettingsManager.getShape(storage), "squircle");
});
