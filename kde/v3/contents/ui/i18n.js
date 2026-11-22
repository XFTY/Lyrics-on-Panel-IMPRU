.pragma library

.import "i18n/zh_TW.js" as ZhTW
.import "i18n/en.js" as En
.import "i18n/es.js" as Es
.import "i18n/ru.js" as Ru
.import "i18n/de.js" as De

var ZhTWTable = ZhTW.table;
var EnTable = En.table;
var EsTable = Es.table;
var RuTable = Ru.table;
var DeTable = De.table;

var indexes = {
    "zh_TW": ZhTWTable,
    "en": EnTable,
    "es": EsTable,
    "ru": RuTable,
    "de": DeTable,
};

var languageCodes = ["zh_CN", "zh_TW", "en", "es", "ru", "de"];

function languageForIndex(index) {
    return languageCodes[index] || "zh_CN";
}

function tr(language, text) {
    if (!text)
        return text;
    var result = text;
    if (language && language !== "zh_CN") {
        var dict = indexes[language];
        if (dict && dict[text])
            result = dict[text];
    }
    for (var i = 2; i < arguments.length; ++i)
        result = String(result).replace("%" + (i - 1), arguments[i]);
    return result;
}
