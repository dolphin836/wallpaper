package handler

import (
	"net/http"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/i18n"
)

// Content localization happens at the HTTP boundary: handlers resolve the
// response language from Accept-Language and overwrite the user-visible
// text fields with the stored translation before serialization (original
// text is the fallback). Owner-only surfaces (the add-to-collection picker,
// the admin console) intentionally skip this and show the original text.

func requestLang(r *http.Request) string { return i18n.FromRequest(r) }

func localizeCategories(lang string, cs []model.Category) {
	for i := range cs {
		cs[i].Name = cs[i].NameI18n.Pick(lang, cs[i].Name)
	}
}

func localizeTags(lang string, ts []model.Tag) {
	for i := range ts {
		ts[i].Name = ts[i].NameI18n.Pick(lang, ts[i].Name)
	}
}

func localizeCollection(lang string, c *model.Collection) {
	c.Title = c.TitleI18n.Pick(lang, c.Title)
	c.Description = c.DescriptionI18n.Pick(lang, c.Description)
}

func localizeCollections(lang string, cs []model.Collection) {
	for i := range cs {
		localizeCollection(lang, &cs[i])
	}
}
