#!/usr/bin/env python3
"""Regression tests for the repository-owned Graphify APEXlang extractor."""

from __future__ import annotations

import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "graphify_apexlang_extractor.py"


class ExtractorPresenceTests(unittest.TestCase):
    def test_canonical_extractor_is_tracked_in_the_repository(self) -> None:
        self.assertTrue(
            MODULE_PATH.is_file(),
            "scripts/graphify_apexlang_extractor.py is missing",
        )


@unittest.skipUnless(MODULE_PATH.is_file(), "canonical extractor is missing")
class ApexlangExtractorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("graphify_apexlang_extractor", MODULE_PATH)
        assert spec and spec.loader
        cls.module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.module
        spec.loader.exec_module(cls.module)

    def setUp(self) -> None:
        scratch = REPO_ROOT / "scratch"
        scratch.mkdir(exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix="apexlang-extractor-test.", dir=scratch))

    def tearDown(self) -> None:
        shutil.rmtree(self.root)

    def extract(self, source: str, relative: str = "apps/DEMO/102/pages/p00004-home.apx") -> dict:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")
        return self.module.extract_apexlang(path)

    def edge_tuples(self, result: dict) -> set[tuple[str, str, str]]:
        return {
            (edge["source"], edge["target"], edge["relation"])
            for edge in result["edges"]
        }

    def test_exposes_graphify_extractor_entry_point(self) -> None:
        self.assertTrue(
            hasattr(self.module, "extract_apexlang"),
            "extract_apexlang(path) is missing",
        )

    def test_extracts_architectural_containment_and_source_lines(self) -> None:
        result = self.extract(
            """page 4 (
    name: Home
    region categories (
        name: Categories
    )
    dynamicAction open-search (
        name: Open Search
    )
    process create-order (
        name: Create Order
    )
)
"""
        )

        self.assertNotIn("error", result)
        nodes = {node["id"]: node for node in result["nodes"]}
        self.assertEqual(nodes["apex_app_102_page_4"]["label"], "Page 4: Home")
        self.assertEqual(nodes["apex_app_102_page_4"]["source_location"], "L1")
        self.assertEqual(
            nodes["apex_app_102_page_4_region_categories"]["label"],
            "Region: Categories",
        )
        self.assertEqual(
            nodes["apex_app_102_page_4_dynamic_action_open_search"]["label"],
            "Dynamic Action: Open Search",
        )
        self.assertEqual(
            nodes["apex_app_102_page_4_process_create_order"]["label"],
            "Process: Create Order",
        )
        edges = self.edge_tuples(result)
        self.assertIn(("apex_app_102", "apex_app_102_page_4", "contains"), edges)
        self.assertIn(
            (
                "apex_app_102_page_4",
                "apex_app_102_page_4_region_categories",
                "contains",
            ),
            edges,
        )

    def test_extracts_application_and_shared_components(self) -> None:
        result = self.extract(
            """app 102 (
    name: APEXToGo
)
list navigation-menu (
    name: Navigation Menu
)
lov restaurant-lov (
    name: Restaurants
)
authorization must-not-be-public-user (
    name: Must Not Be Public User
)
""",
            "apps/DEMO/102/application.apx",
        )

        nodes = {node["id"]: node for node in result["nodes"]}
        self.assertEqual(nodes["apex_app_102"]["label"], "App 102: APEXToGo")
        self.assertIn("apex_app_102_list_navigation_menu", nodes)
        self.assertIn("apex_app_102_lov_restaurant_lov", nodes)
        self.assertIn("apex_app_102_authorization_must_not_be_public_user", nodes)
        edges = self.edge_tuples(result)
        self.assertIn(
            ("apex_app_102", "apex_app_102_list_navigation_menu", "contains"),
            edges,
        )

    def test_keeps_nonarchitectural_components_out_of_nodes(self) -> None:
        result = self.extract(
            """page 4 (
    button checkout (
        name: Checkout
    )
    pageItem P4_QUERY (
        name: Query
    )
    region cards (
        column NAME (
        )
    )
)
"""
        )

        node_ids = {node["id"] for node in result["nodes"]}
        self.assertFalse(any("checkout" in node_id for node_id in node_ids))
        self.assertFalse(any("p4_query" in node_id for node_id in node_ids))
        self.assertFalse(any("column" in node_id for node_id in node_ids))
        self.assertIn("apex_app_102_page_4_region_cards", node_ids)

    def test_scopes_same_named_regions_by_application_and_page(self) -> None:
        first = self.extract("page 4 (\n region summary (\n )\n)\n")
        second = self.extract(
            "page 5 (\n region summary (\n )\n)\n",
            "apps/DEMO/103/pages/p00005-summary.apx",
        )

        first_ids = {node["id"] for node in first["nodes"]}
        second_ids = {node["id"] for node in second["nodes"]}
        self.assertIn("apex_app_102_page_4_region_summary", first_ids)
        self.assertIn("apex_app_103_page_5_region_summary", second_ids)
        self.assertFalse(first_ids & second_ids - {""})

    def test_ignores_delimiters_inside_fences_comments_arrays_and_values(self) -> None:
        result = self.extract(
            '''page 4 (
    // a comment with ) and {
    css {
        inline:
            ```css
            .x::after { content: ")"; }
            ```
    }
    appearance {
        templateOptions: [
            #DEFAULT#
            body-height-fill
        ]
    }
    region content (
    )
)
'''
        )

        self.assertNotIn("error", result)
        self.assertIn(
            "apex_app_102_page_4_region_content",
            {node["id"] for node in result["nodes"]},
        )

    def test_reports_unbalanced_component_or_fence_as_error(self) -> None:
        component = self.extract("page 4 (\n region broken (\n )\n")
        fence = self.extract("page 4 (\n code: ```plsql\n begin null; end;\n)\n")

        self.assertEqual(component["nodes"], [])
        self.assertIn("unclosed component", component["error"])
        self.assertEqual(fence["nodes"], [])
        self.assertIn("unclosed multiline fence", fence["error"])

    def test_output_is_stable_across_repeated_extraction(self) -> None:
        source = "page 4 (\n region categories (\n )\n)\n"
        first = self.extract(source)
        second = self.extract(source)
        self.assertEqual(first, second)

    def test_extracts_navigation_security_and_component_references(self) -> None:
        result = self.extract(
            """page 8 (
    name: Cart
    security {
        authorizationScheme: @must-not-be-public-user
    }
    region cart-lines (
        appearance {
            template: @/content-block
        }
        source {
            listOfValues: @restaurant-lov
        }
        action open-item (
            behavior {
                target: {
                    page: 7
                }
            }
        )
    )
)
list navigation-menu (
    entry cart (
        link { target: { page: 8 } }
    )
    entry faq (
        link {
            targetUrl: f?p=&APP_ID.:13:&APP_SESSION.
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        self.assertIn(
            (
                "apex_app_102_page_8",
                "apex_app_102_authorization_must_not_be_public_user",
                "secured_by",
            ),
            edges,
        )
        self.assertIn(
            (
                "apex_app_102_page_8_region_cart_lines",
                "apex_app_102_lov_restaurant_lov",
                "references_component",
            ),
            edges,
        )
        self.assertIn(
            (
                "apex_app_102_page_8_region_cart_lines",
                "apex_app_102_page_7",
                "navigates_to",
            ),
            edges,
        )
        self.assertIn(
            (
                "apex_app_102_list_navigation_menu",
                "apex_app_102_page_8",
                "navigates_to",
            ),
            edges,
        )
        self.assertIn(
            (
                "apex_app_102_list_navigation_menu",
                "apex_app_102_page_13",
                "navigates_to",
            ),
            edges,
        )

    def test_extracts_sql_reads_writes_and_plsql_calls(self) -> None:
        result = self.extract(
            """page 8 (
    region cart-lines (
        source {
            sqlQuery:
                ```sql
                select i.name
                  from sample_restaurant_items i
                  join sample_restaurant_order_items oi on oi.item_id = i.id
                 where i.notes <> 'from not_a_table'
                   -- join ignored_comment_table x on 1 = 1
                ```
        }
    )
    process checkout (
        source {
            plsqlCode:
                ```plsql
                insert into sample_restaurant_orders(id) values (1);
                update sample_restaurant_order_items set quantity = 2;
                sample_restaurant_manage_orders.create_order;
                apex_collection.create_collection('FROM ALSO_NOT_A_TABLE');
                ```
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        region = "apex_app_102_page_8_region_cart_lines"
        process = "apex_app_102_page_8_process_checkout"
        self.assertIn((region, "sample_restaurant_items", "reads_from"), edges)
        self.assertIn((region, "sample_restaurant_order_items", "reads_from"), edges)
        self.assertIn((process, "sample_restaurant_orders", "writes_to"), edges)
        self.assertIn((process, "sample_restaurant_order_items", "writes_to"), edges)
        self.assertIn(
            (process, "sample_restaurant_manage_orders_create_order", "calls"),
            edges,
        )
        all_targets = {target for _, target, _ in edges}
        self.assertNotIn("not_a_table", all_targets)
        self.assertNotIn("ignored_comment_table", all_targets)
        self.assertNotIn("also_not_a_table", all_targets)
        self.assertNotIn("apex_collection_create_collection", all_targets)

    def test_extracts_unqualified_authorization_and_inline_code(self) -> None:
        result = self.extract(
            """page 8 (
    security {
        authorizationScheme: mustNotBePublicUser
    }
    region order-summary (
        source {
            sqlQuery: select id from sample_restaurant_orders
        }
    )
    process submit-order (
        source {
            plsqlCode: sample_restaurant_manage_orders.create_order;
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        node_ids = {node["id"] for node in result["nodes"]}
        self.assertIn(
            "apex_app_102_authorization_mustnotbepublicuser",
            node_ids,
            "built-in authorization references must have a graph endpoint",
        )
        self.assertIn(
            (
                "apex_app_102_page_8",
                "apex_app_102_authorization_mustnotbepublicuser",
                "secured_by",
            ),
            edges,
        )
        self.assertIn(
            (
                "apex_app_102_page_8_region_order_summary",
                "sample_restaurant_orders",
                "reads_from",
            ),
            edges,
        )
        self.assertIn(
            (
                "apex_app_102_page_8_process_submit_order",
                "sample_restaurant_manage_orders_create_order",
                "calls",
            ),
            edges,
        )

    def test_ignores_self_navigation_and_theme_template_list_references(self) -> None:
        result = self.extract(
            """page 8 (
    action refresh-cart (
        behavior {
            target: { page: 8 }
        }
    )
)
theme universal-theme (
    componentDefaults {
        list: @/links-list
    }
)
"""
        )

        edges = self.edge_tuples(result)
        self.assertNotIn(
            ("apex_app_102_page_8", "apex_app_102_page_8", "navigates_to"),
            edges,
        )
        self.assertNotIn(
            ("apex_app_102", "apex_app_102_list_links_list", "references_component"),
            edges,
        )

    def test_does_not_scan_non_sql_fences_for_database_dependencies(self) -> None:
        result = self.extract(
            '''page 4 (
    region banner (
        css {
            inline:
                ```css
                .update .Badge { content: "from fake_table"; }
                ```
        }
        content {
            html:
                ```html
                <p>Delete from fake_orders and update Icon.</p>
                ```
        }
    )
)
'''
        )

        database_edges = {
            edge
            for edge in self.edge_tuples(result)
            if edge[2] in {"reads_from", "writes_to", "calls"}
        }
        self.assertEqual(database_edges, set())

    def test_does_not_treat_extract_operands_or_record_fields_as_dependencies(self) -> None:
        result = self.extract(
            """page 41 (
    process measure-load (
        source {
            plsqlCode:
                ```plsql
                begin
                    for c1 in (
                        select extract(day from diff) total_days
                          from (select systimestamp - created_on diff
                                  from sample_restaurant_orders)
                    ) loop
                        :P41_TOTAL := c1.total_days;
                    end loop;
                    sample_restaurant_manage_orders.create_order;
                end;
                ```
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        process = "apex_app_102_page_41_process_measure_load"
        self.assertIn((process, "sample_restaurant_orders", "reads_from"), edges)
        self.assertIn(
            (process, "sample_restaurant_manage_orders_create_order", "calls"),
            edges,
        )
        targets = {target for _, target, _ in edges}
        self.assertNotIn("diff", targets)
        self.assertNotIn("c1_total_days", targets)

    def test_resolves_owner_substitution_prefixed_database_objects(self) -> None:
        result = self.extract(
            """page 3 (
    region history (
        source {
            sqlQuery:
                ```sql
                select h.id
                  from #OWNER#.OOW_DEMO_SALES_HISTORY h
                  join "#OWNER#"."OOW_DEMO_ITEMS" i on i.id = h.item_id
                ```
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        region = "apex_app_102_page_3_region_history"
        self.assertIn((region, "oow_demo_sales_history", "reads_from"), edges)
        self.assertIn((region, "oow_demo_items", "reads_from"), edges)
        targets = {target for _, target, _ in edges}
        self.assertFalse(
            [target for target in targets if target.startswith("owner_")],
            "the #OWNER# substitution prefix must not become part of a node id",
        )

    def test_does_not_treat_comment_markers_inside_values_as_comments(self) -> None:
        result = self.extract(
            """page 4 (
    region promo (
        link: "https://apps.example.com/ords/f?p=102:7:0::NO"
    )
    region notes (
        help {
            text: "an unterminated /* marker inside a value"
        }
        source {
            sqlQuery: select id from notes_table
        }
    )
)
"""
        )

        self.assertIsNone(
            result.get("error"),
            "a comment marker inside a quoted value must not break the parse",
        )
        edges = self.edge_tuples(result)
        self.assertIn(
            ("apex_app_102_page_4_region_promo", "apex_app_102_page_7", "navigates_to"),
            edges,
            "a '//' inside a URL value must not be treated as a line comment",
        )
        self.assertIn(
            ("apex_app_102_page_4_region_notes", "notes_table", "reads_from"),
            edges,
        )

    def test_does_not_treat_the_for_update_clause_as_a_write(self) -> None:
        result = self.extract(
            """page 5 (
    region locked (
        source {
            sqlQuery: select id from orders_table for update of quantity nowait
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        region = "apex_app_102_page_5_region_locked"
        self.assertIn((region, "orders_table", "reads_from"), edges)
        self.assertFalse(
            [edge for edge in edges if edge[2] == "writes_to"],
            "a FOR UPDATE row-lock clause is not a write",
        )

    def test_does_not_treat_a_delete_target_as_a_read(self) -> None:
        result = self.extract(
            """page 6 (
    process purge (
        source {
            plsqlCode: delete from purge_table where id = 1;
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        process = "apex_app_102_page_6_process_purge"
        self.assertIn((process, "purge_table", "writes_to"), edges)
        self.assertNotIn(
            (process, "purge_table", "reads_from"),
            edges,
            "DELETE FROM is a write, not a read",
        )

    def test_does_not_treat_a_dml_column_list_as_a_procedure_call(self) -> None:
        result = self.extract(
            """page 7 (
    process audit (
        source {
            plsqlCode: insert into app_data.audit_log(id) values (1);
        }
    )
)
"""
        )

        edges = self.edge_tuples(result)
        process = "apex_app_102_page_7_process_audit"
        self.assertIn((process, "app_data_audit_log", "writes_to"), edges)
        self.assertNotIn(
            (process, "app_data_audit_log", "calls"),
            edges,
            "a schema-qualified INSERT target is not a procedure call",
        )

    def test_ignores_schema_qualified_dual(self) -> None:
        result = self.extract(
            """page 9 (
    region clock (
        source {
            sqlQuery: select systimestamp from sys.dual
        }
    )
)
"""
        )

        targets = {target for _, target, _ in self.edge_tuples(result)}
        self.assertFalse(
            [target for target in targets if "dual" in target],
            "sys.dual is not application architecture",
        )

    def test_declared_authorization_replaces_an_earlier_synthetic_reference(self) -> None:
        result = self.extract(
            """app 102 (
    page 10 (
        security {
            authorizationScheme: admin-only
        }
    )
    authorization admin-only (
        name: Administrators Only
    )
)
"""
        )

        node_id = "apex_app_102_authorization_admin_only"
        nodes = {node["id"]: node for node in result["nodes"]}
        self.assertIn(node_id, nodes)
        node = nodes[node_id]
        self.assertNotIn(
            "synthetic_reference",
            node.get("metadata", {}),
            "the real declaration must replace a forward reference",
        )
        self.assertEqual(
            node["source_location"],
            "L7",
            "the node must point at the declaration, not the first reference",
        )

    def test_disambiguates_repeated_component_identifiers_in_one_page(self) -> None:
        result = self.extract(
            """page 11 (
    region items (
        source {
            sqlQuery: select id from first_table
        }
    )
    region items (
        source {
            sqlQuery: select id from second_table
        }
    )
)
"""
        )

        containment = {
            target for source, target, relation in self.edge_tuples(result)
            if relation == "contains" and source == "apex_app_102_page_11"
        }
        self.assertEqual(
            len(containment),
            2,
            "two sibling declarations must not collapse into one node",
        )
        reads = {
            (source, target) for source, target, relation in self.edge_tuples(result)
            if relation == "reads_from"
        }
        self.assertEqual(
            len({source for source, _ in reads}),
            2,
            "each sibling region must own its own database dependency",
        )

    def test_database_reference_labels_do_not_depend_on_first_seen_spelling(self) -> None:
        template = """page 12 (
    region one (
        source {{
            sqlQuery: select id from {first}
        }}
    )
    region two (
        source {{
            sqlQuery: select id from {second}
        }}
    )
)
"""
        forward = self.extract(
            template.format(first="Orders_Table", second="ORDERS_TABLE"),
            relative="apps/DEMO/102/pages/p00012-a.apx",
        )
        reverse = self.extract(
            template.format(first="ORDERS_TABLE", second="Orders_Table"),
            relative="apps/DEMO/102/pages/p00012-b.apx",
        )

        def label_of(result: dict) -> str:
            return next(
                node["label"] for node in result["nodes"] if node["id"] == "orders_table"
            )

        self.assertEqual(
            label_of(forward),
            label_of(reverse),
            "reference labels must be canonical, not order-dependent",
        )


if __name__ == "__main__":
    unittest.main()
