"use client";

import { useState, useEffect } from "react";
import { apiFetch, getToken } from "@/lib/api";
import { useRouter } from "next/navigation";

interface AppUpdate {
  id: string;
  version: string;
  title: string;
  body: string;
  created_at: string;
}

export default function UpdatesPage() {
  const router = useRouter();
  const [updates, setUpdates] = useState<AppUpdate[]>([]);
  const [loading, setLoading] = useState(true);

  const [version, setVersion] = useState("");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [publishing, setPublishing] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  useEffect(() => {
    if (!getToken()) {
      router.push("/login");
      return;
    }
    loadUpdates();
  }, []);

  async function loadUpdates() {
    setLoading(true);
    try {
      const res = await apiFetch("/admin/updates");
      if (res.ok) {
        setUpdates(await res.json());
      }
    } catch {}
    setLoading(false);
  }

  async function publishUpdate(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setSuccess("");
    if (!version.trim()) {
      setError("Version is required");
      return;
    }
    setPublishing(true);
    try {
      const res = await apiFetch("/admin/updates", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ version, title, body }),
      });
      if (res.ok) {
        setSuccess("Update published successfully!");
        setVersion("");
        setTitle("");
        setBody("");
        loadUpdates();
      } else {
        const data = await res.json().catch(() => ({}));
        setError(data.error || "Failed to publish update");
      }
    } catch {
      setError("Network error");
    }
    setPublishing(false);
  }

  return (
    <div className="min-h-screen bg-gray-950 text-white p-8">
      <div className="max-w-3xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <h1 className="text-2xl font-bold">App Updates</h1>
          <button
            onClick={() => router.push("/")}
            className="text-sm text-gray-400 hover:text-white"
          >
            Back to Dashboard
          </button>
        </div>

        {/* Publish form */}
        <form
          onSubmit={publishUpdate}
          className="bg-gray-900 rounded-xl p-6 mb-8 space-y-4"
        >
          <h2 className="text-lg font-semibold mb-2">Publish New Update</h2>

          <div>
            <label className="block text-sm text-gray-400 mb-1">
              Version *
            </label>
            <input
              type="text"
              value={version}
              onChange={(e) => setVersion(e.target.value)}
              placeholder="e.g. 2.1.0"
              className="w-full bg-gray-800 rounded-lg px-4 py-2 text-white border border-gray-700 focus:border-blue-500 focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Title</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="e.g. New Features & Improvements"
              className="w-full bg-gray-800 rounded-lg px-4 py-2 text-white border border-gray-700 focus:border-blue-500 focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">
              Release Notes
            </label>
            <textarea
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="What's new in this version..."
              rows={6}
              className="w-full bg-gray-800 rounded-lg px-4 py-2 text-white border border-gray-700 focus:border-blue-500 focus:outline-none resize-y"
            />
          </div>

          {error && (
            <p className="text-red-400 text-sm">{error}</p>
          )}
          {success && (
            <p className="text-green-400 text-sm">{success}</p>
          )}

          <button
            type="submit"
            disabled={publishing}
            className="bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white font-semibold px-6 py-2 rounded-lg transition"
          >
            {publishing ? "Publishing..." : "Publish Update"}
          </button>
        </form>

        {/* Updates list */}
        <h2 className="text-lg font-semibold mb-4">Published Updates</h2>
        {loading ? (
          <p className="text-gray-500">Loading...</p>
        ) : updates.length === 0 ? (
          <p className="text-gray-500">No updates published yet.</p>
        ) : (
          <div className="space-y-4">
            {updates.map((u) => (
              <div
                key={u.id}
                className="bg-gray-900 rounded-xl p-5 border border-gray-800"
              >
                <div className="flex items-center justify-between mb-2">
                  <span className="font-mono text-blue-400 font-semibold">
                    v{u.version}
                  </span>
                  <span className="text-xs text-gray-500">
                    {new Date(u.created_at).toLocaleDateString()}
                  </span>
                </div>
                {u.title && (
                  <h3 className="font-semibold text-white mb-1">{u.title}</h3>
                )}
                {u.body && (
                  <p className="text-sm text-gray-400 whitespace-pre-line">
                    {u.body}
                  </p>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
