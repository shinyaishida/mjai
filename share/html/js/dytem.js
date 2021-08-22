let Repeated;

window.Dytem = {
  init() {
    return Dytem.addChildrenField($('body'), null, Dytem);
  },
  assign(obj, elem) {
    let childObj;
    let childElem;
    elem || (elem = Dytem);
    if (typeof obj === 'string') {
      return elem.text(obj);
    } if (obj instanceof Array) {
      elem.clear();
      const results = [];
      for (let i = 0; i < obj.length; i += 1) {
        childObj = obj[i];
        childElem = elem.append();
        results.push(Dytem.assign(childObj, childElem));
      }
      return results;
    }
    const results2 = [];
    for (let name in obj) {
      childObj = obj[name];
      if (name === 'text') {
        results2.push(elem.text(childObj));
      } else if (name === 'html') {
        results2.push(elem.html(childObj));
      } else if (elem[name]) {
        results2.push(Dytem.assign(childObj, elem[name]));
      } else if (elem.attr) {
        results2.push(elem.attr(name, childObj));
      } else {
        throw `unknown field: ${name}`;
      }
    }
    return results2;
  },
  addChildrenField(elem, prefix, target) {
    return elem.find('[id]').each((i, child) => {
      const childId = $(child).attr('id');
      if (prefix) $(child).removeAttr('id');
      const escPrefix = prefix ? prefix.replace(/\./, '\\.') : '';
      if (childId.match(new RegExp(`^${escPrefix}([^\\.]+)$`))) {
        const name = RegExp.$1;
        target[name] = ($(child).hasClass('repeated'))
          ? new Repeated(childId, $(child))
          : $(child);
        return target[name];
      }
    });
  },
};

Repeated = (function () {
  function Repeated(id, placeholder) {
    this.id = id;
    this.placeholder = placeholder;
    this.template = $(document.getElementById(this.id));
    this.elements = [];
  }

  Repeated.prototype.append = function () {
    let lastElem; let
      newElem;
    if (this.elements.length > 0) {
      lastElem = this.elements[this.elements.length - 1];
    } else {
      lastElem = this.placeholder;
    }
    newElem = this.template.clone();
    newElem.removeAttr('id');
    Dytem.addChildrenField(newElem, `${this.id}.`, newElem);
    newElem.show();
    lastElem.after(newElem);
    this.elements.push(newElem);
    return newElem;
  };

  Repeated.prototype.at = function (idx) {
    return this.elements[idx];
  };

  Repeated.prototype.size = function () {
    return this.elements.length;
  };

  Repeated.prototype.resize = function (n) {
    let elem;
    if (n < this.elements.length) {
      const ref = this.elements.slice(n);
      for (let i = 0; i < ref.length; i += 1) {
        elem = ref[i];
        elem.remove();
      }
      return ([].splice.apply(this.elements, [n, 9e9].concat([])), []);
    } if (n > this.elements.length) {
      const results = [];
      const ref3 = this.elements.length;
      for (let i = this.elements.length; ref3 <= n ? i < n : i > n; i += ref3 <= n ? 1 : -1) {
        results.push(this.append());
      }
      return results;
    }
  };

  Repeated.prototype.clear = function () {
    for (let i = 0; i < this.elements.length; i += 1) {
      this.elements[i].remove();
    }
    this.elements = [];
    return this.elements;
  };

  return Repeated;
}());
