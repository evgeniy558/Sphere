import Link from "next/link";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 p-8">
      <h1 className="text-2xl font-semibold text-white">Sphere Admin</h1>
      <div className="flex flex-col gap-3">
        <Link
          href="/login"
          className="rounded-xl bg-violet-600 px-6 py-3 font-medium text-white hover:bg-violet-500 text-center"
        >
          Войти
        </Link>
        <Link
          href="/users"
          className="rounded-xl bg-gray-800 px-6 py-3 font-medium text-white hover:bg-gray-700 text-center"
        >
          Users
        </Link>
        <Link
          href="/updates"
          className="rounded-xl bg-blue-600 px-6 py-3 font-medium text-white hover:bg-blue-500 text-center"
        >
          App Updates
        </Link>
      </div>
    </main>
  );
}
