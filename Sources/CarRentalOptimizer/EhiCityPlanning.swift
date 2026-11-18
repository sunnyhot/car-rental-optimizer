/// Kept separate so the live JavaScript city plan is exercised by JavaScriptCore tests.
func makeEhiCityPlanningScript() -> String {
    """
    const planEhiCityEntries = (entries, currentCityId, radiusKm) => entries
      .map(entry => ({
        ...entry,
        isCurrentCity: String(cityId(entry.city)) === String(currentCityId),
        distanceKm: Number.isFinite(entry.distanceKm) && entry.distanceKm >= 0 ? entry.distanceKm : Number.POSITIVE_INFINITY
      }))
      .filter(entry => entry.isCurrentCity || (Number.isFinite(entry.distanceKm) && entry.distanceKm <= radiusKm))
      .sort((a, b) => {
        if (a.isCurrentCity !== b.isCurrentCity) return a.isCurrentCity ? -1 : 1;
        if (a.distanceKm !== b.distanceKm) return a.distanceKm - b.distanceKm;
        return cityName(a.city).localeCompare(cityName(b.city), 'zh-Hans-CN');
      });
    """
}
