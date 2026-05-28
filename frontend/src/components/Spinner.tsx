export default function Spinner() {
  return (
    <div className="flex justify-center py-12">
      {/* Archive-token spinner — hair as the soft ring, ink as the sweep.
          The previous indigo-600 ring was a pre-Archive holdover that clashed
          with the cooled paper/ink palette. */}
      <div className="h-8 w-8 animate-spin rounded-full border-[3px] border-hair border-t-ink" />
    </div>
  );
}
